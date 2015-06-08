# https://api.hubic.com/docs/#/server-side
# http://docs.openstack.org/api/openstack-object-storage/1.0/content/authentication-examples-curl.html


require 'pathname'
require 'uri'
require 'time'

require 'json'
require 'faraday'
require 'nokogiri'

# TODO
#  - verify scope (requested == granted)
#  - better scope handling
#  - deal with state string
#  - refresh token and credentials

# X-Storage-Url
# X-Auth-Token

require_relative 'hubic/version'
require_relative 'hubic/store'
require_relative 'hubic/openstack'
require_relative 'hubic/file_ops'

class Hubic
    class Error < StandardError
        class Auth < Error
        end
        class NotFound < Error
        end
        class Exists < Error
        end

    end

    # Set the default client Id to use
    def self.default_client_id=(client_id)
        @@client_id = client_id
    end

    # Set the default client Secret to use
    def self.default_client_secret=(client_secret)
        @@client_secret = client_secret
    end

    # Set the default redirect URI to use
    def self.default_redirect_uri=(redirect_uri)
        @@redirect_uri = redirect_uri
    end

    # Create a Hubic handler
    # @param user [String]
    # @param password [String]
    # @param store 
    # @param force [true, false]
    # @param password_requester
    # @return [Hubic] an Hubic handler
    def self.for_user(user, password=nil, 
                      store: Store.new_file(user), force: false, &password_requester)
        h = Hubic.new(@@client_id, @@client_secret, @@redirect_uri)
        h.for_user(user, password, 
                   store: store, force: force, &password_requester)
        h
    end


    # Create a Hubic handler
    # @param client_id
    # @param client_secret
    # @param redirect_uri
    def initialize(client_id     = @@client_id,
                   client_secret = @@client_secret,
                   redirect_uri  = @@redirect_uri)
        @store         = nil
        @refresh_token = nil
        @client_id     = client_id
        @client_secret = client_secret
        @redirect_uri  = redirect_uri
        @conn          = Faraday.new('https://api.hubic.com') do |faraday|
            faraday.request  :url_encoded
            faraday.adapter  :net_http
            faraday.options.params_encoder =  Faraday::FlatParamsEncoder
        end
        @default_container = "default"
    end

    # Initialize the Hubic handler to perform operations on behalf of the user
    # @param user [String]
    # @param password [String]
    # @param store 
    # @param force [true, false]
    # @param password_requester
    def for_user(user, password=nil,
                 store: Store.new_file(user), force: false, &password_requester)
        @store         = store
        @refresh_token = @store['refresh_token'] if @store && !force

        if @refresh_token
            data = refresh_access_token
            @access_token  = data[:access_token]
            @expires_at    = data[:expires_at  ]
        else
            password ||= password_requester.call(user) if password_requester
            if password.nil?
                raise ArgumentError, "password requiered for user authorization"
            end
            code = get_request_code(user, password)
            data = get_access_token(code)
            @access_token  = data[:access_token ]
            @expires_at    = data[:expires_in   ]
            @refresh_token = data[:refresh_token]
            if @store
                @store['refresh_token'] = @refresh_token
                @store.save
            end
        end
    end






    def account
        api_hubic(:get, '/1.0/account')
    end

    def credentials
        api_hubic(:get, '/1.0/account/credentials')
    end

    def usage
        api_hubic(:get, '/1.0/account/usage')
    end


    
    # Make a call to the Hubic API
    # @param method [:get, :post, :delete]
    # @param path
    # @param params [Hash]
    # @return [Hash]
    def api_hubic(method, path, params=nil)
        r = @conn.method(method).call(path) do |req|
            req.headers['Authorization'] = "Bearer #{@access_token}"
            req.params = params if params
        end
        JSON.parse(r.body)
    end

    private

    # Obtain a request code from the Hubic server.
    # We will ask for the code, and validate the form on the user behalf.
    #
    # @param user [String]
    # @param password [String]
    # @return [String] the request code
    def get_request_code(user, password)
        # Request code (retrieve user confirmation form)
        r = @conn.get '/oauth/auth', {
            :client_id     => @client_id,
            :response_type => 'code',
            :redirect_uri  => @redirect_uri,
            :scope         => 'account.r,usage.r,links.drw,credentials.r',
            :state         => 'random'
        }

        # Autofill confirmation 
        params = {}
        doc = Nokogiri::HTML(r.body)
        doc.css('input').each {|i|
            case i[:name]
            when 'login'
                params[:login   ] = user
                next
            when 'user_pwd'
                params[:user_pwd] = password
                next
            end
            
            case i[:type]
            when 'checkbox', 'hidden', 'text'
                (params[i[:name]] ||= []) << i[:value] if i[:name]
            end
        }
        if params.empty?
            raise Error, "unable to autofill confirmation form"
        end

        # Confirm and get code
        r = @conn.post '/oauth/auth', params
        q = Hash[URI.decode_www_form(URI(r[:location]).query)]

        case r.status
        when 302
            q['code']
        when 400, 401, 500
            raise Error::Auth, "#{q['error']} #{q['error_description']}"
        else 
            raise Error::Auth, "unhandled response code (#{r.status})"
        end
    end

    # Request an access token, this will also acquiere a refresh token.
    # @param code [String] the request code
    # @return Hash
    def get_access_token(code)
        r = @conn.post '/oauth/token', {
            :code          => code,
            :redirect_uri  => @redirect_uri,
            :grant_type    => 'authorization_code',
            :client_id     => @client_id,
            :client_secret => @client_secret
        }
        j = JSON.parse(r.body)
        case r.status
        when 200
            {   :acces_token   => j['access_token'],
                :expires_at    => Time.parse(r[:date]) + j['expires_in'].to_i,
                :refresh_token => j['refresh_token']
            }
        when 400, 401, 500
            raise Error::Auth, "#{j['error']} #{j['error_description']}"
        else 
            raise Error::Auth, "unhandled response code (#{r.status})"
        end
    end

    # Refresh the access token
    # @return Hash
    def refresh_access_token
        if @refresh_token.nil?
            raise Error, "refresh_token was not previously acquiered" 
        end
        r = @conn.post '/oauth/token', {
            :refresh_token => @refresh_token,
            :grant_type    => 'refresh_token',
            :client_id     => @client_id,
            :client_secret => @client_secret
        }
        j = JSON.parse(r.body)
        case r.status
        when 200
            {   :access_token => j['access_token'],
                :expires_at   => Time.parse(r[:date]) + j['expires_in'].to_i
            }
        when 400, 401, 500
            raise Error::Auth, "#{j['error']} #{j['error_description']}"
        else 
            raise Error::Auth, "unhandled response code (#{r.status})"
        end
    end

end




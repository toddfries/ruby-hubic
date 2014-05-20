require 'uri'
require 'net/http'
require 'net/https'
require 'json'


class Hubic
    class Container
        attr_reader :name, :count, :bytes, :metadata
        def initialize(hubic, name)
            @hubic    = hubic
            @name     = name.dup.freeze
            j, h      = @hubic.api_openstack(:head, @name)
            @count    = h['x-container-object-count'].to_i
            @bytes    = h['x-container-bytes-used'  ].to_i
            @etag     = h['etag'                    ]
            @metadata = Hash[h.map {|k,v|
                              if k =~ /^x-container-meta-(.*)/
                                  [ $1, v ]
                              end
                             }.compact].freeze
        end

        def [](key)
            @metadata[key]
        end

        def empty?
            @count == 0
        end

        def destroy!
            j, h = @hubic.api_openstack(:delete, @name)
            j
        end

        def object(path)
        end

        def objects()
        end


    end

    class Object
        def initialize(hubic)
            @hubic = hubic
        end
    end

    def get_object(obj, dst=nil, size: nil, offset: 0, &block)
        container, path, uri = normalize_object(obj)

        if !(IO   === dst) && !dst.respond_to?(:write) &&
           !(Proc === dst) && !dst.respond_to?(:call)
            raise ArgumentError, "unsupported destination"
        end

        meta = {}

        hdrs = {}
        hdrs['X-Auth-Token'] = @os[:token]

        if size
            hdrs['Range'] = sprintf("bytes=%d-%d", offset, offset + size - 1)
        end

        http = Net::HTTP.new(uri.host, uri.port)
        if uri.scheme == 'https'
            http.use_ssl = true
            # http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        http.start


        http.request_get(uri.request_uri, hdrs) {|response|
            case response
            when Net::HTTPSuccess
            when Net::HTTPRedirection
                fail "http redirect is not currently handled"
            when Net::HTTPUnauthorized
                # TODO: Need to refresh token
            else
                fail "resource unavailable: #{uri} (#{response.class})"
            end

            lastmod = Time.parse(response['last-modified']) rescue nil
            length  = response.content_length
            type    = response['content-type']
            meta    = { :lastmod => lastmod, 
                        :length  => length, 
                        :type    => type 
                      }
            
            if block
                block.call(meta)
            end
            
            response.read_body {|segment|
                if    IO   === dst            then dst.write(segment)
                elsif Proc === dst            then dst.call(segment)
                elsif dst.respond_to?(:write) then dst.write(segment)
                elsif dst.respond_to?(:call ) then dst.call(segment)
                end
                
                if block
                    block.call(segment)
                end
            }
        }            
        if block
            block.call(:done)
        end

        meta
    ensure
        http.finish unless http.nil?
    end

    def put_object(src, obj, &block)
        container, path, uri = normalize_object(obj)

        r = @conn.put(uri) do |req|
            req.headers['X-Auth-Token'] = @os[:token]
            req.params[:file] = Faraday::UploadIO.new(src, 'text/plain')
        end
        puts r.inspect
    end

    def objects(container = @default_container, 
                path: nil, limit: nil, gt: nil, lt: nil)
        path = path[1..-1] if path && path[0] == ?/
        p    = { path: path, limit: limit, marker: gt, end_marker: lt 
               }.delete_if {|k,v| v.nil? }            
        j,   = api_openstack(:get, container, p)
        Hash[j.map {|o| [ o['name'], {
                              :hash    => o['hash'], 
                              :lastmod => Time.parse(o['last_modified']),
                              :size    => o['bytes'].to_i,
                              :type    => o['content_type']
                          } ] } ]
    end

    def containers
        j, = api_openstack(:get, '/')
        Hash[j.map {|c| [ c['name'], { :size  => c['bytes'].to_i, 
                                       :count => c['count'].to_i } ] } ]
    end

    def container(name)
        Container.new(self, name)
    end

    def default_container=(name)
        @default_container = name
    end

    def api_openstack(method, path, params=nil)
        openstack_setup_refresh

        params ||= {}
        params[:format] ||= :json

        p = "#{@os[:endpoint]}#{'/' if path[0] != ?/}#{path}"
        r = @conn.method(method).call(p) do |req|
            req.headers['X-Auth-Token'] = @os[:token]
            req.params = params
        end

        if r.body.nil? || r.body.empty?
        then [ nil,                r.headers ]
        else [ JSON.parse(r.body), r.headers ]
        end
    end


    def openstack_setup_refresh(force: false)
        return unless force || @os.nil? || @os[:expires] <= Time.now

        data     = self.credentials
        endpoint = data['endpoint']
        token    = data['token']
        expires  = Time.parse(data['expires'])

        openstack_setup(endpoint, token, expires)
    end

    def openstack_setup(endpoint, token, expires)
        conn = Faraday.new  do |faraday|
            faraday.request  :url_encoded
            faraday.adapter  :net_http
            faraday.options.params_encoder =  Faraday::FlatParamsEncoder
        end
        @os = {
            :expires  => expires,
            :token    => token,
            :endpoint => endpoint,
            :conn     => conn
        }
    end

    def normalize_object(obj)
        c, p = case obj
               when String 
                   [ @default_container, obj ]
               when Hash 
                   [ obj[:name] || obj[:path], 
                     (obj[:container] || @default_container).to_s ]
               when Array  
                   case obj.length
                   when 1 then [ @default_container, obj ]
                   when 2 then Symbol === obj[1] ? [ obj[1], obj[0] ] : obj
                   else raise ArguementError
                   end
               end
        c = c.to_s
        p = p[1..-1] if p[0] == ?/
        [ c, p, URI("#{@os[:endpoint]}/#{c}/#{p}") ]
    end

end

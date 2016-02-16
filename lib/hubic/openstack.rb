require 'uri'
require 'net/http'
require 'net/https'
require 'json'


class Hubic
    TYPE_OCTET_STREAM = 'application/octet-stream'
    TYPE_DIRECTORY    = 'application/directory'

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

    def parse_response_for_meta(response)
        { :lastmod => (Time.parse(response['last-modified']) rescue nil),
          :length  => response.content_length,
          :size    => response.content_length.to_i,
          :type    => response['content-type'],
          :etag    => response['etag']
        }
    end


    def get_metadata(obj)
        container, path, uri = normalize_object(obj)
        if uri.nil?
            fail "normalize_obj(#{obj}) returned a nil uri"
        end
        meta = {}
        hdrs = {}
        hdrs['X-Auth-Token'] = @os[:token]

        http = init_http( uri )

        retrycount = 0
        maxretry = 3
        doretry = 0
        newlocation = nil
        loop do
        begin
        http.request_head(uri.request_uri, hdrs) {|response|
            case response
            when Net::HTTPSuccess
                meta = parse_response_for_meta(response)
            when Net::HTTPNotFound
                meta = nil
            when Net::HTTPRequestTimeOut
                doretry = 1
            when Net::HTTPServiceUnavailable
                doretry = 1
            when Net::HTTPBadGateway
                doretry = 1
            when Net::HTTPRedirection
                location = response['location']
                fail "redirected to #{location}, not yet handled"
            when Net::HTTPUnauthorized
                # TODO: Need to refresh token
                puts "TODO: Need to refresh token here"
            else
                fail "resource unavailable: #{uri} (#{response.class} = #{response})"
            end
        }
        rescue NoMethodError
            fail "NoMehodError: uri = #{uri}"
        end
        retrycount += 1
        break unless retrycount < maxretry && doretry == 1
        end

        meta
    ensure
        http.finish unless http.nil?
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

        http = init_http(uri)

        retrycount = 0
        maxretry = 3
        doretry = 0
        loop do
        http.request_get(uri.request_uri, hdrs) {|response|
            case response
            when Net::HTTPSuccess
            when Net::HTTPRedirection
                location = response['location']
                fail "redirected to #{location}, not yet handled"
            when Net::HTTPUnauthorized
                # TODO: Need to refresh token
            when Net::HTTPRequestTimeOut
                doretry = 1
            else
                fail "resource unavailable: #{uri} (#{response.class} = #{response})"
            end

            meta    = parse_response_for_meta(response)

            if block
                puts "block: #{block}"
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
        retrycount += 1
        break unless retrycount < maxretry && doretry == 1
        end
        if block
            block.call(:done)
        end

        meta
    ensure
        http.finish unless http.nil?
    end

    def copy_object(obj, dst=nil)
        container, path, uri = normalize_object(obj)

        meta = {}

        hdrs = {}
        hdrs['X-Auth-Token'] = @os[:token]

        http = init_http(uri)

        retrycount = 0
        maxretry = 3
        doretry = 0
        loop do
        http.copy(uri.request_uri, hdrs) {|response|
            case response
            when Net::HTTPSuccess
            when Net::HTTPRedirection
                location = response['location']
                fail "redirected to #{location}, not yet handled"
            when Net::HTTPUnauthorized
                # TODO: Need to refresh token
            when Net::HTTPRequestTimeOut
                doretry = 1
            else
                fail "resource unavailable: #{uri} (#{response.class} = #{response})"
            end

            meta    = parse_response_for_meta(response)

        }
        retrycount += 1
        break unless retrycount < maxretry && doretry == 1
        end

        meta
    ensure
        http.finish unless http.nil?
    end

    def put_object(obj, src, type = TYPE_OCTET_STREAM, &block)
        container, path, uri = normalize_object(obj)
        case src
        when String
            io = File.open(src)
        when NilClass
            io = StringIO.new('')
        else
            raise ArgumentError, 'Not Implemented Yet'
        end

        hdrs = {}
        hdrs['X-Auth-Token'     ] = @os[:token]
        hdrs['Transfer-Encoding'] = 'chunked'
        hdrs['Content-Type'     ] = type

        http = init_http(uri)

        request = Net::HTTP::Put.new(uri.request_uri, hdrs)
        request.body_stream = io
        retrycount = 0
        maxretry = 3
        doretry = 0
        loop do
        http.request(request) {|response|
            case response
            when Net::HTTPSuccess
                #puts "put_object: success! #{response}"
            when Net::HTTPRedirection
                location = response['location']
                fail "redirected to #{location}, not yet handled"
            when Net::HTTPUnauthorized
                # TODO: Need to refresh token
            when Net::HTTPRequestTimeOut
                doretry = 1
            when Net::HTTPServiceUnavailable
                doretry = 1
            when Errno::EPIPE
                doretry = 1
            when Net::HTTPBadGateway
                doretry = 1
            when Net::HTTPRequestEntityTooLarge
                fail "Uploading a file (#{path}) that is too large for hubic"
            else
                fail "resource unavailable: #{uri} (#{response.class} = #{response})"
            end

            #puts response.inspect
        }
        retrycount += 1
        break unless retrycount < maxretry && doretry == 1
        end
        if block
            puts "put_object(#{obj}): block: #{block}"
            block.call(:done)
        end
    ensure
        io.close unless io.nil?
        http.finish unless http.nil?
    end

    def delete_object(obj, &block)
        container, path, uri = normalize_object(obj)

        hdrs = {}
        hdrs['X-Auth-Token'     ] = @os[:token]

        http = init_http(uri)

        request = Net::HTTP::Delete.new(uri.request_uri, hdrs)
        retrycount = 0
        maxretry = 3
        doretry = 0
        loop do
        http.request(request) {|response|
            case response
            when Net::HTTPNoContent
            when Net::HTTPSuccess
            when Net::HTTPRedirection
                location = response['location']
                fail "redirected to #{location}, not yet handled"
            when Net::HTTPUnauthorized
                # TODO: Need to refresh token
            when Net::HTTPRequestTimeOut
                doretry = 1
            when Net::HTTPNotFound
                meta = nil
                puts "Not Found"
            else
                fail "resource unavailable: #{uri} (#{response.class} = #{response})"
            end

            puts response.inspect
        }
        retrycount += 1
        break unless retrycount < maxretry && doretry == 1
        end
        if block
            block.call(:done)
        end
    ensure
        http.finish unless http.nil?
    end

    # List objects store in a container.
    #
    # @param container [String] the name of the container.
    # @return [Array] the list of objects (as a Hash)
    def objects(container = @default_container,
                path: nil, limit: nil, gt: nil, lt: nil)
        path = path[1..-1] if path && path[0] == ?/
        p    = { path: path, limit: limit, marker: gt, end_marker: lt
               }.delete_if {|k,v| v.nil? }
        j,h   = api_openstack(:get, container, p)
        Hash[j.map {|o| [ o['name'], {
                              :hash    => o['hash'],
                              :lastmod => Time.parse(o['last_modified']),
                              :size    => o['bytes'].to_i,
                              :type    => o['content_type'],
                              :contuse => h['x-container-bytes-used'],
                              :contoct => h['x-container-object-coun'],
                              :storpol => h['x-storage-policy'],
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

    def get_var(var)
        if var == 'default_container'
            @default_container
        else
            nil
        end
    end

    def api_openstack(method, path, params=nil)
        openstack_setup_refresh

        params ||= {}
        params[:format] ||= :json

        p = "#{@os[:endpoint]}#{'/' if path[0] != ?/}#{path}"
        r = @os[:conn].method(method).call(p) do |req|
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
        return if data.nil?
        exptmp = data['expires']
        endpoint = data['endpoint']
        token    = data['token']
        if exptmp.nil?
            expires = nil
        else
            expires  = Time.parse(exptmp)
        end

        openstack_setup(endpoint, token, expires)
    end

    def openstack_setup(endpoint, token, expires)
        conn = Faraday.new  do |faraday|
            faraday.request  :multipart
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
        openstack_setup_refresh # TODO: no need to refresh just get the endpoint

        c, p = case obj
               when String
                   [ @default_container, obj ]
               when Hash
                   if obj[:name].nil?
                       path = obj[:path]
                   else
                       path = obj[:name]
                   end
                   if obj[:container].nil?
                       cont = @default_container.to_s
                   else
                       cont = obj[:container]
                   end
                   [ cont, path ]
               when Array
                   case obj.length
                   when 1 then [ @default_container, obj ]
                   when 2 then Symbol === obj[1] ? [ obj[1], obj[0] ] : obj
                   else raise ArguementError
                   end
               else
                   raise ArgumentError
               end
        c = c.to_s
        p = p[1..-1] if p[0] == ?/
        [ c, p, URI("#{@os[:endpoint]}/#{c}/#{p}") ]
    end

    def init_http(uri)
        h = Net::HTTP.new(uri.host, uri.port)
        if uri.scheme == 'https'
            h.use_ssl = true
            # h.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        #h.read_timeout(600)
        h.start
        h
    end

end

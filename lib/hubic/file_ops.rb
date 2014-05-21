require 'mime/types'

class Hubic

    def download(obj, dst=nil, size: nil, offset: 0, &block)
        # Handle file name or nil as a posible destination
        io   = nil
        dst  = Pathname(dst) if String === dst
        _dst = case dst
               when Pathname then io = dst.open('w')
               when NilClass then io = StringIO.new
               else dst
               end

        # Get object
        meta = get_object(obj, _dst, size: size, offset: offset, &block)

        # If file name update the timestamp
        if (Pathname === dst) && meta[:lastmod]
            dst.utime(meta[:lastmod], meta[:lastmod])
        end
        
        # If destination is nil, returns the downloaded file
        # insteaded of the meta data
        if dst.nil?
        then io.flush.string
        else meta
        end        
    ensure
        io.close unless io.nil?
    end

    def upload(src, obj, type='application/octet-stream', &block)
        case src
        when String, Pathname
            type = (MIME::Types.of(src).first ||
                    MIME::Types['application/octet-stream'].first).content_type
        end
        put_object(obj, src, type, &block)
    end

    def copy(src, dst)
        raise "not implemented yet"
    end
    
    def move(src, dst)
        raise "not implemented yet"
    end

    def delete(src)
        raise "not implemented yet"
    end

    def checksum(src)
        raise "not implemented yet"
    end


    def list(path = '/', container = @default_container)
        objects(container, path: path)
    end

end

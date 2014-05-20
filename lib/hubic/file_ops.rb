class Hubic

    # File operations
    #######################################################################

    def download(obj, dst=nil, size: nil, offset: 0, &block)
        io   = nil
        dst  = Pathname(dst) if String === dst
        _dst = case dst
               when Pathname then io = dst.open('w')
               when NilClass then io = StringIO.new
               else dst
               end

        meta = get_object(obj, _dst, size: size, offset: offset, &block)

        if (Pathname === dst) && meta[:lastmod]
            dst.utime(meta[:lastmod], meta[:lastmod])
        end

        if dst.nil?
        then io.flush.string
        else meta
        end        
    ensure
        io.close unless io.nil?
    end

    def upload(src, obj, &block)
        put_object(src, obj, &block)
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

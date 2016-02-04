require 'mime/types'

class Hubic
    # Create directory
    # @param obj 
    # @param parents [true, false] 
    def mkdir(obj, parents: false)
        container, path, = normalize_object(obj)

        # Check for parents (create or raise error)
        parent = File.dirname(path) 
        if ! %w[. /].include?(parent)
            if (meta = get_metadata([container, parent])).nil?
                if parents
                    mkdir([container, parent], parents: parents)
                else
                    raise Error, "parent doesn't exist"
                end
            elsif meta[:type] != TYPE_DIRECTORY
                raise Error, "parent is not a directory"
            end
        end

        # Check if place is already taken before creating directory
        if (meta = get_metadata(obj)).nil?
            put_object(obj, nil, TYPE_DIRECTORY)
        elsif meta[:type] != TYPE_DIRECTORY
            raise Error::Exists, "a file already exists"
        elsif !parents
            raise Error::Exists, "the directory already exists"
        end
    end

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

    def upload(src, obj, type=TYPE_OCTET_STREAM, &block)
        case src
        when String, Pathname
            type = (MIME::Types.of(src).first ||
                    MIME::Types[TYPE_OCTET_STREAM].first).content_type
        end
        if (meta = get_metadata(obj)).nil?
        then
            #puts "no file exists of this name, good deal!"
        elsif meta[:type] != TYPE_DIRECTORY
            puts "over-writing existing file #{obj} of #{meta[:size]}bytes"
        else
            srcbn = File.basename(src)
            newobj = "#{obj}/#{srcbn}"
            puts "#{obj} is a dir, changing destination to #{newobj}"
            obj = newobj
        end
        begin
            put_object(obj, src, type, &block)
        rescue SocketError
            puts "Sorry, a socket error occurred, can we gracfully fix this?"
        end
    end

    def copy(src, dst)
        raise "not implemented yet"
    end
    
    def move(src, dst)
        raise "not implemented yet"
    end

    def delete(obj)
	# Check if obj exists before deleting
	if (meta = get_metadata(obj)).nil?
            puts "delete: the object #{obj} does not exist"
	else
	    puts delete_object(obj)
	end
    end

    def md5(obj)
        meta = get_metadata(obj)
        meta[:etag]
    end


    def list(path = '/', container = @default_container)
        objects(container, path: path)
    end

    def stat(obj)
        get_metadata(obj)
    end

end

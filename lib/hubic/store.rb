require 'yaml'

class Hubic
class Store 
    FILE = "#{ENV['HOME']}/.hubic"

    extend Forwardable
    def_delegator :@data, :[]
    def_delegator :@data, :[]=

    def initialize(file = FILE, user = nil)
        @file   = file
        @user   = user
        @data   = Hash(begin
                           if data = YAML.load_file(@file)
                               @user.nil? ? data : data[@user]
                           end
                       rescue Errno::ENOENT
                       end)
    end
    
    def self.[](user)
        self.new(file = FILE, user)
    end
    
    def save
        data = if @user
                   ( begin 
                         YAML.load_file(@file)
                     rescue Errno::ENOENT
                     end || {} ).merge(@user => @data)
               else
                   @data
               end
        File.open(@file, 'w', 0600) {|io|
            io.write(data.to_yaml)
        }
    end
end
end

# -*- ruby -*-

require "rbconfig"
require "rubygems"
require "bundler/setup"
require "yard"

include Rake::DSL


Bundler::GemHelper.install_tasks

YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb']   # optional
#  t.options = ['--any', '--extra', '--opts'] # optional
end

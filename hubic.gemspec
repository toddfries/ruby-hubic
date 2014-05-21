# -*- encoding: utf-8 -*-
$:.unshift File.expand_path("../lib", __FILE__)
require "hubic/version"

Gem::Specification.new do |s|
  s.name        = "hubic"
  s.version     = Hubic::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = [ "Stephane D'Alu" ]
  s.email       = ["sdalu@sdalu.com" ]
  s.homepage    = "http://github.com/sdalu/ruby-hubic"
  s.summary     = "Manage your Hubic account from Ruby"
  s.description = "Manage your Hubic account from Ruby"

  s.add_dependency "faraday", "~>0.9"
  s.add_dependency "mime-types"
  s.add_dependency "highline"
  s.add_dependency "nokogiri"
  s.add_development_dependency "rake"

  s.files = `git ls-files`.split("\n")
  s.executables = `git ls-files`.split("\n").map{|f| f =~ /^bin\/(.*)/ ? $1 : nil}.compact
  s.require_path = 'lib'
end

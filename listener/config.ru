#!/usr/bin/env ruby
require_relative 'logging'
require 'async'
require_relative 'src/server'
require 'rack/handler/falcon'

# disable logging for Async::IO::Socket, Falcon::Server
Console.logger.enable Class, 3
Console.logger.enable Falcon::Server, 3

Async do
  Rack::Handler::Falcon.run StackManagerApi, Port: 5050, Host: '0.0.0.0'
end

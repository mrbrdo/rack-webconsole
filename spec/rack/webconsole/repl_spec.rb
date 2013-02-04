require 'spec_helper'
require 'ostruct'

module Rack
  describe Webconsole::Repl do

    it 'initializes with an app' do
      @app = stub
      @repl = Webconsole::Repl.new(@app)

      @repl.instance_variable_get(:@app).must_equal @app
    end

    describe "#call" do
      let(:app) { lambda { |env| [200, {'Content-Type' => 'text/plain'}, ['hello world']] } }
      let(:repl) { Webconsole::Repl.new(app) }
      before(:each) do
        @app = app
      end
      let(:environment) { {} }
      let(:use_post) { true }

      # sends input query using the webconsole, returning the response
      # query: The pry input to use
      # token:(optional) The authentication token
      def response_to(query, token = nil)
        params = {'query' => query }
        params['token'] = token if token
        request = OpenStruct.new(:params => params, :post? => use_post)
        Rack::Request.stubs(:new).returns request
        repl.call(environment)
      end

      # same as send_input, but extracts the result out of the query
      def query(input, token = nil)
        response = response_to(input, token)
        MultiJson.load(response.last.first)['result']
      end

      def with_token(token)
        Webconsole::Repl.class_variable_set(:@@tokens, {token => Time.now + 30 * 60})
      end

      it 'handles a request with a correct token' do
        with_token('abc')
        response_to('unknown_method', 'abc').wont_equal app.call(environment)
      end

      it 'rejects a request with an invalid token' do
        with_token('abc')
        response_to('unknown_method', 'cba').must_equal app.call(environment)
      end

      describe "with a valid token" do
        before(:each) do
          Webconsole::Repl.stubs(:token_valid?).returns(true)
        end

        it 'evaluates the :query param in a sandbox and returns the result' do
          query('a = 4; a * 2').must_include "8"
        end

        it 'displays data sent to stdout' do
          query('puts "hello world"').must_include "hello world"
        end

        it 'displays data sent to stderr' do
          query('warn "Warning"').must_include "Warning"
        end

        it 'displays data sent to stdout after a delay' do
          query('.sleep 0.5; echo command output').must_include 'command output'
        end

        it "Outputs the result of the computation after an stdout data" do
          output = query('puts "stdout";"result"')
          result_loc = output.match("result").begin(0)
          stdout_loc = output.match("stdout").begin(0)
          (stdout_loc < result_loc).must_equal true
        end

        it 'displays stdout data from external processes' do
          query('.echo command output').must_include 'command output'
        end

        it 'maintains local state in subsequent calls thanks to an evil global variable' do
          query('a = 4')
          query('a * 8').must_include "32"
        end

        it "returns any found errors prepended with 'Error:'" do
          query('unknown_method').must_match /Error:/
        end
      end

      describe "with non-post requests" do
        let(:use_post) { false }
        it "rejects the request" do
          with_token('abc')
          response = response_to('unknown_method', 'abc')
          response.must_equal app.call(environment)
        end
      end

    end

    describe 'class methods' do
      describe '#request= and #request' do
        it 'returns the request object' do
          request = stub
          Webconsole::Repl.request = request
          Webconsole::Repl.request.must_equal request
        end
      end
    end

  end
end

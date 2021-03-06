# frozen_string_literal: true

require 'logger'
require 'stringio'

RSpec.describe Faraday::DetailedLogger::Middleware do
  TestError = Class.new(StandardError)

  let(:log) { StringIO.new }
  let(:logger) { Logger.new(log) }

  context 'by default' do
    it 'logs to STDOUT' do
      expect { connection(nil).get('/temaki') }.to output.to_stdout
    end
  end

  context 'with tags configured' do
    it 'logs prepends the tags to each line' do
      connection(logger, %w[ebi]).get('/temaki')
      log.rewind
      log.readlines.each do |line|
        expect(line).to match(/: \[ebi\] /)
      end
    end
  end

  context 'for the HTTP request-portion' do
    it 'logs request method and URI at an INFO level' do
      connection(logger).get('/temaki')
      log.rewind
      expect(log.read).to match(%r{\bINFO\b.+\bGET http://sushi\.com/temaki\b})
    end

    it 'logs the requested body at a DEBUG level' do
      connection(logger).post(
        '/nigirizushi',
        { 'body' => 'content' },
        { user_agent: 'Faraday::DetailedLogger' }
      )
      log.rewind
      curl = <<~CURL.strip
        Content-Type: application/x-www-form-urlencoded
        User-Agent: Faraday::DetailedLogger

        body=content
      CURL
      expect(log.read).to match(/\bDEBUG\b.+#{Regexp.escape(curl.inspect)}/)
    end
  end

  context 'for the HTTP response-portion' do
    it 'logs a 2XX response status code at an INFO level' do
      connection(logger).get('/oaiso', c: 200)
      log.rewind
      expect(log.read).to match(/\bINFO\b.+\bHTTP 200\b/)
    end

    it 'logs a 3XX response status code at an INFO level' do
      connection(logger).get('/oaiso', c: 301)
      log.rewind
      expect(log.read).to match(/\bINFO\b.+\bHTTP 301\b/)
    end

    it 'logs a 4XX response status code at a WARN level' do
      connection(logger).get('/oaiso', c: 401)
      log.rewind
      expect(log.read).to match(/\bWARN\b.+\bHTTP 401\b/)
    end

    it 'logs a 5XX response status code at an WARN level' do
      connection(logger).get('/oaiso', c: 500)
      log.rewind
      expect(log.read).to match(/\bWARN\b.+\bHTTP 500\b/)
    end

    it 'logs the response headers and body at a DEBUG level' do
      connection(logger).post('/nigirizushi')
      log.rewind
      curl = <<~CURL.strip
        Content-Type: application/json

        {"id":"1"}
      CURL
      expect(log.read).to match(/\bDEBUG\b.+#{Regexp.escape(curl.inspect)}/)
    end

    it 'logs errors which occur during the request and re-raises them' do
      logger = Logger.new(log = StringIO.new)

      expect do
        connection(logger).get('/error')
      end.to raise_error(TestError, 'An error occurred during the request')

      log.rewind
      expect(log.read).to match(
        /\bERROR\b.+\bTestError - An error occurred during the request \(.+\)$/
      )
    end
  end

  private

  def connection(logger = nil, *tags)
    Faraday.new(url: 'http://sushi.com') do |builder|
      builder.request(:url_encoded)
      builder.response(:detailed_logger, logger, *tags)
      builder.adapter(:test) do |stub|
        stub.get('/temaki') do
          [200, { 'Content-Type' => 'text/plain' }, 'temaki']
        end
        stub.post('/nigirizushi') do
          [200, { 'Content-Type' => 'application/json' }, '{"id":"1"}']
        end
        stub.get('/oaiso') do |env|
          code = env.respond_to?(:params) ? env.params['c'] : env[:params]['c']
          [code.to_i, { 'Content-Type' => 'application/json' }, code]
        end
        stub.get('/error') do
          raise TestError, 'An error occurred during the request'
        end
      end
    end
  end
end

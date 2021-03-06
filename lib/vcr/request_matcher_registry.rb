require 'vcr/errors'

module VCR
  # Keeps track of the different request matchers.
  class RequestMatcherRegistry

    # The default request matchers used for any cassette that does not
    # specify request matchers.
    DEFAULT_MATCHERS = [:method, :uri]

    # @private
    class Matcher < Struct.new(:callable)
      def matches?(request_1, request_2)
        callable.call(request_1, request_2)
      end
    end

    # @private
    class URIWithoutParamsMatcher < Struct.new(:params_to_ignore)
      def partial_uri_from(request)
        URI(request.uri).tap do |uri|
          return request.uri unless uri.query # ignore uris without params, e.g. "http://example.com/"

          uri.query = uri.query.split('&').tap { |params|
            params.map! do |p|
              key, value = p.split('=')
              key.gsub!(/\[\]\z/, '') # handle params like tag[]=
              [key, value]
            end

            params.reject! { |p| params_to_ignore.include?(p.first) }
            params.map!    { |p| p.join('=') }
          }.join('&')
        end
      end

      def call(request_1, request_2)
        partial_uri_from(request_1) == partial_uri_from(request_2)
      end

      def to_proc
        lambda { |r1, r2| call(r1, r2) }
      end
    end

    # @private
    def initialize
      @registry = {}
      register_built_ins
    end

    # @private
    def register(name, &block)
      if @registry.has_key?(name)
        warn "WARNING: There is already a VCR request matcher registered for #{name.inspect}. Overriding it."
      end

      @registry[name] = Matcher.new(block)
    end

    # @private
    def [](matcher)
      @registry.fetch(matcher) do
        matcher.respond_to?(:call) ?
          Matcher.new(matcher) :
          raise_unregistered_matcher_error(matcher)
      end
    end

    # Builds a dynamic request matcher that matches on a URI while ignoring the
    # named query parameters. This is useful for dealing with non-deterministic
    # URIs (i.e. that have a timestamp or request signature parameter).
    #
    # @example
    #   without_timestamp = VCR.request_matchers.uri_without_param(:timestamp)
    #
    #   # use it directly...
    #   VCR.use_cassette('example', :match_requests_on => [:method, without_timestamp]) { }
    #
    #   # ...or register it as a named matcher
    #   VCR.configure do |c|
    #     c.register_request_matcher(:uri_without_timestamp, &without_timestamp)
    #   end
    #
    #   VCR.use_cassette('example', :match_requests_on => [:method, :uri_without_timestamp]) { }
    #
    # @param ignores [Array<#to_s>] The names of the query parameters to ignore
    # @return [#call] the request matcher
    def uri_without_params(*ignores)
      uri_without_param_matchers[ignores]
    end
    alias uri_without_param uri_without_params

  private

    def uri_without_param_matchers
      @uri_without_param_matchers ||= Hash.new do |hash, params|
        params = params.map(&:to_s)
        hash[params] = URIWithoutParamsMatcher.new(params)
      end
    end

    def raise_unregistered_matcher_error(name)
      raise Errors::UnregisteredMatcherError.new \
        "There is no matcher registered for #{name.inspect}. " +
        "Did you mean one of #{@registry.keys.map(&:inspect).join(', ')}?"
    end

    def register_built_ins
      register(:method)  { |r1, r2| r1.method == r2.method }
      register(:uri)     { |r1, r2| r1.uri == r2.uri }
      register(:host)    { |r1, r2| URI(r1.uri).host == URI(r2.uri).host }
      register(:path)    { |r1, r2| URI(r1.uri).path == URI(r2.uri).path }
      register(:body)    { |r1, r2| r1.body == r2.body }
      register(:headers) { |r1, r2| r1.headers == r2.headers }
    end
  end
end


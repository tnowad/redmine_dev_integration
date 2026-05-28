# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module RedmineDevIntegration
  module ProviderClients
    class RepositoryNotFoundError < StandardError; end
    class AuthenticationError < StandardError; end

    class BaseClient
      DEFAULT_TIMEOUT = 10

      def initialize(settings: default_settings, http_getter: nil)
        @settings = settings.is_a?(Hash) ? settings : {}
        @http_getter = http_getter
      end

      def recent_pull_requests(repository:)
        raise NotImplementedError
      end

      def recent_builds(repository:)
        raise NotImplementedError
      end

      def recent_deployments(repository:)
        raise NotImplementedError
      end

      def credentials_missing?
        false
      end

      def paginated_get(uri, headers:, max_pages: 5, max_items: 500, collection_key: nil)
        all_items = []
        page = 0
        next_url = uri.to_s

        while next_url && page < max_pages && all_items.size < max_items
          page += 1
          next_uri = URI(next_url)
          response = perform_request(next_uri, headers: headers)
          body = response.respond_to?(:body) ? response.body : response
          body = body.to_s
          break if body.blank?

          parsed = JSON.parse(body)
          items = if collection_key
                    Array(parsed[collection_key])
                  else
                    Array(parsed)
                  end
          all_items.concat(items)

          next_url = find_next_page(next_uri, response)
        end

        all_items.first(max_items)
      end

      private

      attr_reader :settings, :http_getter

      def default_settings
        Setting.plugin_redmine_dev_integration
      rescue StandardError
        {}
      end

      def setting_value(*keys)
        keys.each do |key|
          return settings[key] if settings.key?(key)

          symbol_key = key.to_sym
          return settings[symbol_key] if settings.key?(symbol_key)
        end

        nil
      end

      def fetch_json(uri, headers: {})
        body = perform_request(uri, headers: headers)
        body = body.body if body.respond_to?(:body)
        body = body.to_s
        return {} if body.blank?

        JSON.parse(body)
      end

      def perform_request(uri, headers: {})
        if http_getter.respond_to?(:call)
          http_getter.call(uri, headers)
        else
          default_http_getter(uri, headers)
        end
      end

      def post_json(uri, body:, headers: {})
        response = post_request(uri, body: body, headers: headers)
        body = response.body if response.respond_to?(:body)
        body = body.to_s
        return {} if body.blank?

        JSON.parse(body)
      end

      def patch_json(uri, body:, headers: {})
        response = patch_request(uri, body: body, headers: headers)
        body = response.body if response.respond_to?(:body)
        body = body.to_s
        return {} if body.blank?

        JSON.parse(body)
      end

      def post_request(uri, body:, headers: {})
        perform_http_request(uri, headers: headers) do |u|
          req = Net::HTTP::Post.new(u.request_uri)
          req.body = JSON.generate(body)
          req
        end
      end

      def patch_request(uri, body:, headers: {})
        perform_http_request(uri, headers: headers) do |u|
          req = Net::HTTP::Patch.new(u.request_uri)
          req.body = JSON.generate(body)
          req
        end
      end

      def put_json(uri, body:, headers: {})
        response = put_request(uri, body: body, headers: headers)
        body = response.body if response.respond_to?(:body)
        body = body.to_s
        return {} if body.blank?

        JSON.parse(body)
      end

      def put_request(uri, body:, headers: {})
        perform_http_request(uri, headers: headers) do |u|
          req = Net::HTTP::Put.new(u.request_uri)
          req.body = JSON.generate(body)
          req
        end
      end

      def default_http_getter(uri, headers)
        perform_http_request(uri, headers: headers) do |u|
          Net::HTTP::Get.new(u.request_uri)
        end
      end

      def perform_http_request(uri, headers: {}, &block)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = DEFAULT_TIMEOUT
        http.read_timeout = DEFAULT_TIMEOUT

        http.start do |conn|
          request = block.call(uri)
          headers.each { |k, v| request[k] = v }
          response = conn.request(request)
          response.value
          response
        end
      end

      def compact_collection(payload, key = nil)
        collection =
          if payload.is_a?(Hash) && key.present?
            payload[key] || payload[key.to_sym]
          else
            payload
          end

        Array(collection)
      end

      def normalize_hash(value)
        raw = value.respond_to?(:to_h) ? value.to_h : value
        raw = raw.stringify_keys if raw.respond_to?(:stringify_keys)
        raw.is_a?(Hash) ? raw : {}
      end

      def parse_time(value)
        return if value.blank?
        return value.in_time_zone if value.respond_to?(:in_time_zone) && !value.is_a?(String)

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def truthy?(value)
        value == true || value.to_s == '1' || value.to_s.casecmp('true').zero?
      end

      def find_next_page(uri, response)
        return nil unless response.respond_to?(:each_header) && response.respond_to?(:[])

        link_header = response['Link']
        if link_header.present?
          links = parse_link_header(link_header)
          return links[:next]
        end

        next_page = response['X-Next-Page']
        if next_page.present?
          new_uri = uri.dup
          params = URI.decode_www_form(new_uri.query || '')
          params.reject! { |k, _| k == 'page' }
          params << ['page', next_page]
          new_uri.query = URI.encode_www_form(params)
          return new_uri.to_s
        end

        nil
      end

      def parse_link_header(link_header)
        links = {}
        link_header.split(',').each do |part|
          section = part.split(';')
          next unless section.size >= 2

          url_match = section[0].strip.match(/<(.+)>/)
          rel_match = section[1].strip.match(/rel="(.+)"/)
          next unless url_match && rel_match

          links[rel_match[1].to_sym] = url_match[1]
        end
        links
      end
    end
  end
end

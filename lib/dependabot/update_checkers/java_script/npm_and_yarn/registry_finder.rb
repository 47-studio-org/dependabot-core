# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/java_script/npm_and_yarn"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn
        class RegistryFinder
          AUTH_TOKEN_REGEX = %r{//(?<registry>.*)/:_authToken=(?<token>.*)$}.freeze

          def initialize(dependency:, credentials:, npmrc_file: nil)
            @dependency = dependency
            @credentials = credentials
            @npmrc_file = npmrc_file
          end

          def registry
            locked_registry || first_registry_with_dependency_details
          end

          def auth_headers
            auth_header_for(auth_token)
          end

          def dependency_url
            "#{registry_url.gsub(%r{/+$}, '')}/#{escaped_dependency_name}"
          end

          private

          attr_reader :dependency, :credentials, :npmrc_file

          def first_registry_with_dependency_details
            @first_registry_with_dependency_details ||=
              known_registries.find do |details|
                Excon.get(
                  "https://#{details['registry'].gsub(%r{/+$}, '')}/"\
                  "#{escaped_dependency_name}",
                  headers: auth_header_for(details["token"]),
                  idempotent: true,
                  **SharedHelpers.excon_defaults
                ).status < 400
              rescue Excon::Error::Timeout, Excon::Error::Socket
                nil
              end&.fetch("registry")

            @first_registry_with_dependency_details ||= "registry.npmjs.org"
          end

          def registry_url
            protocol =
              if private_registry_source_url
                private_registry_source_url.split("://").first
              else
                "https"
              end

            "#{protocol}://#{registry}"
          end

          def auth_header_for(token)
            return {} unless token

            if token.include?(":")
              encoded_token = Base64.encode64(token).delete("\n")
              { "Authorization" => "Basic #{encoded_token}" }
            elsif Base64.decode64(token).ascii_only? &&
                  Base64.decode64(token).include?(":")
              { "Authorization" => "Basic #{token.delete("\n")}" }
            else
              { "Authorization" => "Bearer #{token}" }
            end
          end

          def auth_token
            known_registries.
              find { |cred| cred["registry"] == registry }&.
              fetch("token")
          end

          def locked_registry
            return unless private_registry_source_url

            lockfile_registry =
              private_registry_source_url.
              gsub("https://", "").
              gsub("http://", "")
            detailed_registry =
              known_registries.
              find { |h| h["registry"].include?(lockfile_registry) }&.
              fetch("registry")

            detailed_registry || lockfile_registry
          end

          def known_registries
            @known_registries ||=
              begin
                registries = []
                registries += credentials.
                              select { |cred| cred["type"] == "npm_registry" }

                npmrc_file&.content.to_s.scan(AUTH_TOKEN_REGEX) do
                  next if Regexp.last_match[:registry].include?("${")

                  registries << {
                    "type" => "npm_registry",
                    "registry" => Regexp.last_match[:registry],
                    "token" => Regexp.last_match[:token]
                  }
                end

                registries.uniq
              end
          end

          # npm registries expect slashes to be escaped
          def escaped_dependency_name
            dependency.name.gsub("/", "%2F")
          end

          def private_registry_source_url
            sources = dependency.requirements.
                      map { |r| r.fetch(:source) }.uniq.compact

            # If there are multiple source types, or multiple source URLs, then
            # it's unclear how we should proceed
            if sources.map { |s| [s[:type], s[:url]] }.uniq.count > 1
              raise "Multiple sources! #{sources.join(', ')}"
            end

            # Otherwise we just take the URL of the first private registry
            sources.find { |s| s[:type] == "private_registry" }&.fetch(:url)
          end
        end
      end
    end
  end
end

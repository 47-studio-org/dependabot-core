# frozen_string_literal: true

require "dependabot/file_updaters/java_script/npm_and_yarn"

module Dependabot
  module FileUpdaters
    module JavaScript
      class NpmAndYarn
        # Build a .npmrc file from the lockfile content, credentials, and any
        # committed .npmrc
        class NpmrcBuilder
          CENTRAL_REGISTRIES = %w(
            registry.npmjs.org
            registry.yarnpkg.com
          ).freeze

          def initialize(dependency_files:, credentials:)
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def npmrc_content
            initial_content =
              if npmrc_file then complete_npmrc_from_credentials
              elsif yarnrc_file then build_npmrc_from_yarnrc
              else
                build_npmrc_content_from_lockfile
              end

            return initial_content || "" unless registry_credentials.any?

            ([initial_content] + credential_lines_for_npmrc).compact.join("\n")
          end

          private

          attr_reader :dependency_files, :credentials

          def build_npmrc_content_from_lockfile
            return unless yarn_lock || package_lock
            return unless global_registry

            "registry = https://#{global_registry['registry']}\n"\
            "#{global_registry_auth_line}\n"\
            "always-auth = true"
          end

          def global_registry
            @global_registry ||=
              registry_credentials.find do |cred|
                next false if CENTRAL_REGISTRIES.include?(cred["registry"])

                # If all the URLs include this registry, it's global
                if dependency_urls.all? { |url| url.include?(cred["registry"]) }
                  next true
                end

                # If any unscoped URLs include this registry, it's global
                dependency_urls.
                  reject { |u| u.include?("@") || u.include?("%40") }.
                  any? { |url| url.include?(cred["registry"]) }
              end
          end

          def global_registry_auth_line
            token = global_registry.fetch("token")

            if token.include?(":")
              encoded_token = Base64.encode64(token).delete("\n")
              "_auth = #{encoded_token}"
            elsif Base64.decode64(token).ascii_only? &&
                  Base64.decode64(token).include?(":")
              "_auth = #{token.delete("\n")}"
            else
              "_authToken = #{token}"
            end
          end

          def dependency_urls
            if package_lock
              parsed_package_lock.fetch("dependencies", {}).
                map { |_, details| details["resolved"] }.compact.
                reject { |url| url.start_with?("git") }
            elsif yarn_lock
              yarn_lock.content.scan(/ resolved "(.*?)"/).flatten
            end
          end

          def complete_npmrc_from_credentials
            initial_content =
              npmrc_file.content.
              gsub(/^.*:_authToken=\$.*/, "").
              gsub(/^.*:_auth=\$.*/, "")

            return initial_content unless (cred = registry_credentials.first)

            initial_content.gsub(/^_auth\s*=\s*\${.*}/) do |ln|
              ln.sub(/\${.*}/, cred.fetch("token"))
            end
          end

          def build_npmrc_from_yarnrc
            yarnrc_global_registry =
              yarnrc_file.content.
              lines.find { |line| line.match?(/^\s*registry\s/) }&.
              match(/^\s*registry\s+"(?<registry>[^"]+)"/)&.
              named_captures&.fetch("registry")

            if yarnrc_global_registry
              return "registry = #{yarnrc_global_registry}\n"
            end

            build_npmrc_content_from_lockfile
          end

          def credential_lines_for_npmrc
            lines = []
            registry_credentials.each do |cred|
              registry = cred.fetch("registry")

              lines << registry_scope(registry) if registry_scope(registry)

              token = cred.fetch("token")
              if token.include?(":")
                encoded_token = Base64.encode64(token).delete("\n")
                lines << "//#{registry}/:_auth=#{encoded_token}"
              elsif Base64.decode64(token).ascii_only? &&
                    Base64.decode64(token).include?(":")
                lines << %(//#{registry}/:_auth=#{token.delete("\n")})
              else
                lines << "//#{registry}/:_authToken=#{token}"
              end
            end

            return lines unless lines.any? { |str| str.include?("auth=") }

            # Work around a suspected yarn bug
            ["always-auth = true"] + lines
          end

          def registry_scope(registry)
            # Central registries don't just apply to scopes
            return if CENTRAL_REGISTRIES.include?(registry)

            return unless dependency_urls

            affected_urls = dependency_urls.
                            select { |url| url.include?(registry) }

            scopes = affected_urls.map do |url|
              url.split(/%40|@/)[1]&.split(%r{%2F|/})&.first
            end

            # Registry used for unscoped packages
            return if scopes.include?(nil)

            # This just seems unlikely
            return unless scopes.uniq.count == 1

            "@#{scopes.first}:registry=https://#{registry}/"
          end

          def registry_credentials
            credentials.select { |cred| cred.fetch("type") == "npm_registry" }
          end

          def parsed_package_lock
            @parsed_package_lock ||= JSON.parse(package_lock.content)
          end

          def npmrc_file
            @npmrc_file ||= dependency_files.find { |f| f.name == ".npmrc" }
          end

          def yarnrc_file
            @yarnrc_file ||= dependency_files.find { |f| f.name == ".yarnrc" }
          end

          def yarn_lock
            @yarn_lock ||= dependency_files.find { |f| f.name == "yarn.lock" }
          end

          def package_lock
            @package_lock ||=
              dependency_files.find { |f| f.name == "package-lock.json" }
          end
        end
      end
    end
  end
end

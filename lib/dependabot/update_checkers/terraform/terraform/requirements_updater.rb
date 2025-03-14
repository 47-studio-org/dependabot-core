# frozen_string_literal: true

####################################################################
# For more details on Terraform version constraints, see:          #
# https://www.terraform.io/docs/modules/usage.html#module-versions #
####################################################################

require "dependabot/utils/terraform/version"
require "dependabot/utils/terraform/requirement"
require "dependabot/update_checkers/terraform/terraform"

module Dependabot
  module UpdateCheckers
    module Terraform
      class Terraform
        class RequirementsUpdater
          def initialize(requirements:, latest_version:,
                         tag_for_latest_version:)
            @requirements = requirements
            @tag_for_latest_version = tag_for_latest_version

            return unless latest_version
            return unless version_class.correct?(latest_version)

            @latest_version = version_class.new(latest_version)
          end

          def updated_requirements
            return requirements unless latest_version

            # NOTE: Order is important here. The FileUpdater needs the updated
            # requirement at index `i` to correspond to the previous requirement
            # at the same index.
            requirements.map do |req|
              case req.dig(:source, :type)
              when "git" then update_git_requirement(req)
              when "registry" then update_registry_requirement(req)
              else req
              end
            end
          end

          private

          attr_reader :requirements, :latest_version, :tag_for_latest_version

          def update_git_requirement(req)
            return req unless req.dig(:source, :ref)
            return req unless tag_for_latest_version

            req.merge(source: req[:source].merge(ref: tag_for_latest_version))
          end

          def update_registry_requirement(req)
            return req if req.fetch(:requirement).nil?

            string_req = req.fetch(:requirement).strip
            ruby_req = requirement_class.new(string_req)
            return req if ruby_req.satisfied_by?(latest_version)

            new_req =
              if ruby_req.exact? then latest_version.to_s
              elsif string_req.start_with?("~>")
                update_twiddle_version(string_req).to_s
              else
                update_range(string_req).map(&:to_s).join(", ")
              end

            req.merge(requirement: new_req)
          end

          # Updates the version in a "~>" constraint to allow the given version
          def update_twiddle_version(req_string)
            old_version = requirement_class.new(req_string).
                          requirements.first.last
            updated_version = at_same_precision(latest_version, old_version)
            req_string.sub(old_version.to_s, updated_version)
          end

          def update_range(req_string)
            requirement_class.new(req_string).requirements.flat_map do |r|
              next r if r.satisfied_by?(latest_version)

              case op = r.requirements.first.first
              when "<", "<=" then [update_greatest_version(r, latest_version)]
              when "!=" then []
              else raise "Unexpected operation for unsatisfied req: #{op}"
              end
            end
          end

          def at_same_precision(new_version, old_version)
            release_precision =
              old_version.to_s.split(".").select { |i| i.match?(/^\d+$/) }.count
            prerelease_precision =
              old_version.to_s.split(".").count - release_precision

            new_release =
              new_version.to_s.split(".").first(release_precision)
            new_prerelease =
              new_version.to_s.split(".").
              drop_while { |i| i.match?(/^\d+$/) }.
              first([prerelease_precision, 1].max)

            [*new_release, *new_prerelease].join(".")
          end

          # Updates the version in a "<" or "<=" constraint to allow the given
          # version
          def update_greatest_version(requirement, version_to_be_permitted)
            if version_to_be_permitted.is_a?(String)
              version_to_be_permitted =
                version_class.new(version_to_be_permitted)
            end
            op, version = requirement.requirements.first
            version = version.release if version.prerelease?

            index_to_update =
              version.segments.map.with_index { |seg, i| seg.zero? ? 0 : i }.max

            new_segments = version.segments.map.with_index do |_, index|
              if index < index_to_update
                version_to_be_permitted.segments[index]
              elsif index == index_to_update
                version_to_be_permitted.segments[index] + 1
              else
                0
              end
            end

            requirement_class.new("#{op} #{new_segments.join('.')}")
          end

          def version_class
            Utils::Terraform::Version
          end

          def requirement_class
            Utils::Terraform::Requirement
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/utils"

module Dependabot
  module FileParsers
    class Base
      class DependencySet
        def initialize(dependencies = [])
          unless dependencies.is_a?(Array) &&
                 dependencies.all? { |dep| dep.is_a?(Dependency) }
            raise ArgumentError, "must be an array of Dependency objects"
          end

          @dependencies = dependencies
        end

        attr_reader :dependencies

        def <<(dep)
          unless dep.is_a?(Dependency)
            raise ArgumentError, "must be a Dependency object"
          end

          existing_dependency = dependencies.find { |d| d.name == dep.name }

          return self if existing_dependency&.to_h == dep.to_h

          if existing_dependency
            dependencies[dependencies.index(existing_dependency)] =
              combined_dependency(existing_dependency, dep)
          else
            dependencies << dep
          end

          self
        end

        def +(other)
          unless other.is_a?(DependencySet)
            raise ArgumentError, "must be a DependencySet"
          end

          other.dependencies.each { |dep| self << dep }
          self
        end

        private

        def combined_dependency(old_dep, new_dep)
          package_manager = old_dep.package_manager
          v_cls = Utils.version_class_for_package_manager(package_manager)

          # If we already have a requirement use the existing version
          # (if present). Otherwise, use whatever the lowest version is
          new_version =
            if old_dep.requirements.any? then old_dep.version || new_dep.version
            elsif !v_cls.correct?(new_dep.version) then old_dep.version
            elsif !v_cls.correct?(old_dep.version) then new_dep.version
            elsif v_cls.new(new_dep.version) > v_cls.new(old_dep.version)
              old_dep.version
            else
              new_dep.version
            end

          Dependency.new(
            name: old_dep.name,
            version: new_version,
            requirements: (old_dep.requirements + new_dep.requirements).uniq,
            package_manager: package_manager
          )
        end
      end
    end
  end
end

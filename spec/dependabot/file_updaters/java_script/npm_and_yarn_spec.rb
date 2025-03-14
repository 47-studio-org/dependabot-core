# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/java_script/npm_and_yarn"
require "dependabot/utils/java_script/version"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::JavaScript::NpmAndYarn do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:files) { [package_json, yarn_lock, package_lock] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:package_json) do
    Dependabot::DependencyFile.new(
      content: package_json_body,
      name: "package.json"
    )
  end
  let(:package_json_body) do
    fixture("javascript", "package_files", manifest_fixture_name)
  end
  let(:manifest_fixture_name) { "package.json" }
  let(:package_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: package_lock_body
    )
  end
  let(:package_lock_body) do
    fixture("javascript", "npm_lockfiles", npm_lock_fixture_name)
  end
  let(:npm_lock_fixture_name) { "package-lock.json" }
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: yarn_lock_body
    )
  end
  let(:yarn_lock_body) do
    fixture("javascript", "yarn_lockfiles", yarn_lock_fixture_name)
  end
  let(:yarn_lock_fixture_name) { "yarn.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      previous_version: previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "npm_and_yarn"
    )
  end
  let(:dependency_name) { "fetch-factory" }
  let(:version) { "0.0.2" }
  let(:previous_version) { "0.0.1" }
  let(:requirements) do
    [{
      file: "package.json",
      requirement: "^0.0.2",
      groups: ["dependencies"],
      source: nil
    }]
  end
  let(:previous_requirements) do
    [{
      file: "package.json",
      requirement: "^0.0.1",
      groups: ["dependencies"],
      source: nil
    }]
  end

  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }
    let(:updated_package_json) do
      updated_files.find { |f| f.name == "package.json" }
    end
    let(:updated_npm_lock) do
      updated_files.find { |f| f.name == "package-lock.json" }
    end
    let(:updated_yarn_lock) do
      updated_files.find { |f| f.name == "yarn.lock" }
    end

    it "updates the files" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
      expect(updated_files.count).to eq(3)
    end

    specify { expect { updated_files }.to_not output.to_stdout }

    context "without a lockfile" do
      let(:files) { [package_json] }
      its(:length) { is_expected.to eq(1) }

      context "when nothing has changed" do
        let(:requirements) { previous_requirements }
        specify { expect { updated_files }.to raise_error(/No files/) }
      end
    end

    context "with a shrinkwrap" do
      let(:files) { [package_json, shrinkwrap] }
      let(:shrinkwrap) do
        Dependabot::DependencyFile.new(
          name: "npm-shrinkwrap.json",
          content: shrinkwrap_body
        )
      end
      let(:shrinkwrap_body) do
        fixture("javascript", "shrinkwraps", "npm-shrinkwrap.json")
      end
      let(:updated_shrinkwrap) do
        updated_files.find { |f| f.name == "npm-shrinkwrap.json" }
      end

      it "updates the shrinkwrap" do
        parsed_shrinkwrap = JSON.parse(updated_shrinkwrap.content)
        expect(parsed_shrinkwrap["dependencies"]["fetch-factory"]["version"]).
          to eq("0.0.2")
      end

      context "and a package-json.lock" do
        let(:files) { [package_json, shrinkwrap, package_lock] }

        it "updates the shrinkwrap and the package-lock.json" do
          parsed_shrinkwrap = JSON.parse(updated_shrinkwrap.content)
          expect(parsed_shrinkwrap["dependencies"]["fetch-factory"]["version"]).
            to eq("0.0.2")

          parsed_npm_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_npm_lock["dependencies"]["fetch-factory"]["version"]).
            to eq("0.0.2")
        end
      end
    end

    context "with a git dependency" do
      let(:dependency_name) { "is-number" }
      let(:requirements) do
        [{
          requirement: req,
          file: "package.json",
          groups: ["devDependencies"],
          source: {
            type: "git",
            url: "https://github.com/jonschlinkert/is-number",
            branch: nil,
            ref: ref
          }
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: old_req,
          file: "package.json",
          groups: ["devDependencies"],
          source: {
            type: "git",
            url: "https://github.com/jonschlinkert/is-number",
            branch: nil,
            ref: old_ref
          }
        }]
      end
      let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
      let(:version) { "0c6b15a88bc10cd47f67a09506399dfc9ddc075d" }

      context "without a requirement or reference" do
        let(:req) { nil }
        let(:ref) { "master" }
        let(:old_req) { nil }
        let(:old_ref) { "master" }

        let(:manifest_fixture_name) { "github_dependency_no_ref.json" }
        let(:yarn_lock_fixture_name) { "github_dependency_no_ref.lock" }
        let(:npm_lock_fixture_name) { "github_dependency_no_ref.json" }

        it "only updates the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package-lock.json yarn.lock))

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("github:jonschlinkert/is-number#"\
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

          expect(updated_yarn_lock.content).to include("is-number")
          expect(updated_yarn_lock.content).to_not include("d5ac0584ee")
        end

        context "specified as a full URL" do
          let(:req) { nil }
          let(:ref) { "master" }
          let(:old_req) { nil }
          let(:old_ref) { "master" }

          let(:manifest_fixture_name) { "git_dependency.json" }
          let(:yarn_lock_fixture_name) { "git_dependency.lock" }
          let(:npm_lock_fixture_name) { "git_dependency.json" }

          it "only updates the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package-lock.json yarn.lock))

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("git+https://github.com/jonschlinkert/is-number.git#"\
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

            expect(updated_yarn_lock.content).to include("is-number")
            expect(updated_yarn_lock.content).to include("0c6b15a88b")
            expect(updated_yarn_lock.content).to_not include("af885e2e890")
          end

          context "when the package lock is empty" do
            let(:npm_lock_fixture_name) { "no_dependencies.json" }

            it "updates the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package-lock.json yarn.lock))

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              expect(
                parsed_package_lock["dependencies"]["is-number"]["version"]
              ).to eq("git+https://github.com/jonschlinkert/is-number.git#"\
                      "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
            end
          end

          context "that previously caused problems" do
            let(:manifest_fixture_name) { "git_dependency_git_url.json" }
            let(:yarn_lock_fixture_name) { "git_dependency_git_url.lock" }
            let(:npm_lock_fixture_name) { "git_dependency_git_url.json" }

            let(:dependency_name) { "slick-carousel" }
            let(:requirements) { previous_requirements }
            let(:previous_requirements) do
              [{
                requirement: old_req,
                file: "package.json",
                groups: ["devDependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/brianfryer/slick",
                  branch: nil,
                  ref: old_ref
                }
              }]
            end
            let(:previous_version) do
              "280b560161b751ba226d50c7db1e0a14a78c2de0"
            end
            let(:version) { "a2aa3fec335c50aceb58f6ef6d22df8e5f3238e1" }

            it "only updates the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package-lock.json yarn.lock))

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              npm_lockfile_version =
                parsed_package_lock["dependencies"]["slick-carousel"]["version"]
              expect(npm_lockfile_version).
                to eq("git://github.com/brianfryer/slick.git#"\
                      "a2aa3fec335c50aceb58f6ef6d22df8e5f3238e1")

              expect(updated_yarn_lock.content).
                to include('slick-carousel@git://github.com/brianfryer/slick":')
              expect(updated_yarn_lock.content).to include("a2aa3fec")
              expect(updated_yarn_lock.content).to_not include("280b56016")
            end
          end

          context "that uses ssh" do
            let(:manifest_fixture_name) { "git_dependency_ssh.json" }
            let(:yarn_lock_fixture_name) { "git_dependency_ssh.lock" }
            let(:npm_lock_fixture_name) { "git_dependency_ssh.json" }

            it "only updates the lockfile" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package-lock.json yarn.lock))

              parsed_package_lock = JSON.parse(updated_npm_lock.content)
              npm_lockfile_version =
                parsed_package_lock["dependencies"]["is-number"]["version"]
              expect(npm_lockfile_version).
                to eq("git+ssh://git@github.com/jonschlinkert/is-number.git#"\
                      "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

              expect(updated_yarn_lock.content).to include("is-number")
              expect(updated_yarn_lock.content).to_not include("0c6b15a88bc")
              expect(updated_yarn_lock.content).to_not include("af885e2e890")
              expect(updated_yarn_lock.content).
                to include("is-number@git+ssh://git@github.com:jonschlinkert")
            end
          end

          context "when updating another dependency" do
            let(:dependency_name) { "chalk" }
            let(:version) { "2.3.2" }
            let(:previous_version) { "0.4.0" }
            let(:requirements) do
              [{
                requirement: "2.3.2",
                file: "package.json",
                groups: ["dependencies"],
                source: nil
              }]
            end
            let(:previous_requirements) do
              [{
                requirement: "0.4.0",
                file: "package.json",
                groups: ["dependencies"],
                source: nil
              }]
            end

            it "doesn't remove the git dependency" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package.json package-lock.json yarn.lock))

              parsed_npm_lock = JSON.parse(updated_npm_lock.content)
              expect(parsed_npm_lock["dependencies"]["is-number"]["version"]).
                to eq("git+https://github.com/jonschlinkert/is-number.git#"\
                      "af885e2e890b9ef0875edd2b117305119ee5bdc5")

              expect(updated_yarn_lock.content).
                to include("is-number.git#af885e2e890b9ef0875edd2b117305119ee")
            end

            context "with an npm6 lockfile" do
              let(:npm_lock_fixture_name) { "git_dependency_npm6.json" }
              let(:files) { [package_json, package_lock] }

              it "doesn't update the 'from' entry" do
                expect(updated_files.map(&:name)).
                  to match_array(%w(package.json package-lock.json))

                parsed_npm_lock = JSON.parse(updated_npm_lock.content)
                expect(parsed_npm_lock["dependencies"]["is-number"]["version"]).
                  to eq("git+https://github.com/jonschlinkert/is-number.git#"\
                        "af885e2e890b9ef0875edd2b117305119ee5bdc5")

                expect(parsed_npm_lock["dependencies"]["is-number"]["from"]).
                  to eq("git+https://github.com/jonschlinkert/is-number.git")
              end
            end
          end
        end
      end

      context "with a requirement" do
        # This is npm specific because Yarn doesn't yet support semver
        # requirements in a package.json
        let(:files) { [package_json, package_lock] }
        let(:req) { "^4.0.0" }
        let(:ref) { "master" }
        let(:old_req) { "^2.0.0" }
        let(:old_ref) { "master" }

        let(:manifest_fixture_name) { "github_dependency_semver.json" }
        let(:npm_lock_fixture_name) { "github_dependency_semver.json" }

        it "updates the package.json and the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))

          parsed_package_json = JSON.parse(updated_package_json.content)
          expect(parsed_package_json["devDependencies"]["is-number"]).
            to eq("jonschlinkert/is-number#semver:^4.0.0")

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("github:jonschlinkert/is-number#"\
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end
      end

      context "with a reference" do
        let(:req) { nil }
        let(:ref) { "4.0.0" }
        let(:old_req) { nil }
        let(:old_ref) { "2.0.0" }

        let(:manifest_fixture_name) { "github_dependency.json" }
        let(:yarn_lock_fixture_name) { "github_dependency.lock" }
        let(:npm_lock_fixture_name) { "github_dependency.json" }

        it "updates the package.json and the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json yarn.lock))

          parsed_package_json = JSON.parse(updated_package_json.content)
          expect(parsed_package_json["devDependencies"]["is-number"]).
            to eq("jonschlinkert/is-number#4.0.0")

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("github:jonschlinkert/is-number#"\
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

          expect(updated_yarn_lock.content).
            to include("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end

        context "when using full git URL" do
          let(:manifest_fixture_name) { "git_dependency_ref.json" }
          let(:yarn_lock_fixture_name) { "git_dependency_ref.lock" }
          let(:npm_lock_fixture_name) { "git_dependency_ref.json" }

          it "updates the package.json and the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json yarn.lock))

            parsed_package_json = JSON.parse(updated_package_json.content)
            expect(parsed_package_json["devDependencies"]["is-number"]).
              to eq("https://github.com/jonschlinkert/is-number.git#4.0.0")

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("git+https://github.com/jonschlinkert/is-number.git#"\
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

            expect(updated_yarn_lock.content).
              to include("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end
        end

        context "updating to use the registry" do
          let(:dependency_name) { "is-number" }
          let(:version) { "4.0.0" }
          let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
          let(:requirements) do
            [{
              requirement: "^4.0.0",
              file: "package.json",
              groups: ["devDependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              requirement: nil,
              file: "package.json",
              groups: ["devDependencies"],
              source: {
                type: "git",
                url: "https://github.com/jonschlinkert/is-number",
                branch: nil,
                ref: "d5ac058"
              }
            }]
          end

          let(:manifest_fixture_name) { "git_dependency_commit_ref.json" }
          let(:yarn_lock_fixture_name) { "git_dependency_commit_ref.lock" }
          let(:npm_lock_fixture_name) { "git_dependency_commit_ref.json" }

          it "updates the package.json and the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package.json package-lock.json yarn.lock))

            parsed_package_json = JSON.parse(updated_package_json.content)
            expect(parsed_package_json["devDependencies"]["is-number"]).
              to eq("^4.0.0")

            parsed_package_lock = JSON.parse(updated_npm_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("4.0.0")

            expect(updated_yarn_lock.content).
              to include("is-number@^4.0.0")
          end
        end
      end
    end

    context "with a path-based dependency" do
      let(:files) { [package_json, package_lock, yarn_lock, path_dep] }
      let(:manifest_fixture_name) { "path_dependency.json" }
      let(:npm_lock_fixture_name) { "path_dependency.json" }
      let(:yarn_lock_fixture_name) { "path_dependency.lock" }
      let(:path_dep) do
        Dependabot::DependencyFile.new(
          name: "deps/etag/package.json",
          content: fixture("javascript", "package_files", "etag.json")
        )
      end
      let(:dependency_name) { "lodash" }
      let(:version) { "1.3.1" }
      let(:previous_version) { "1.2.1" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^1.3.1",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^1.2.1",
          groups: ["dependencies"],
          source: nil
        }]
      end

      it "has details of the updated item" do
        parsed_lockfile = JSON.parse(updated_npm_lock.content)

        expect(parsed_lockfile["dependencies"]["lodash"]["version"]).
          to eq("1.3.1")
        expect(updated_yarn_lock.content).to include("lodash@^1.3.1")

        expect(updated_package_json.content).
          to include("\"lodash\": \"^1.3.1\"")
        expect(updated_package_json.content).
          to include("\"etag\": \"file:./deps/etag\"")
      end
    end

    context "with a lerna.json, and lockfiles" do
      let(:files) do
        [
          package_json,
          lerna_json,
          package1,
          package1_yarn_lock,
          package1_npm_lock,
          package2,
          package2_yarn_lock,
          package2_npm_lock,
          other_package_json,
          other_package_yarn_lock,
          other_package_npm_lock
        ]
      end
      let(:manifest_fixture_name) { "lerna.json" }
      let(:lerna_json) do
        Dependabot::DependencyFile.new(
          name: "lerna.json",
          content: fixture("javascript", "lerna", "lerna.json")
        )
      end
      let(:package1) do
        Dependabot::DependencyFile.new(
          name: "packages/package1/package.json",
          content: fixture("javascript", "package_files", "package1.json")
        )
      end
      let(:package1_yarn_lock) do
        Dependabot::DependencyFile.new(
          name: "packages/package1/yarn.lock",
          content: fixture("javascript", "yarn_lockfiles", "package1.lock")
        )
      end
      let(:package1_npm_lock) do
        Dependabot::DependencyFile.new(
          name: "packages/package1/package-lock.json",
          content: fixture("javascript", "npm_lockfiles", "package1.json")
        )
      end
      let(:package2) do
        Dependabot::DependencyFile.new(
          name: "packages/package2/package.json",
          content: fixture("javascript", "package_files", "wildcard.json")
        )
      end
      let(:package2_yarn_lock) do
        Dependabot::DependencyFile.new(
          name: "packages/package2/yarn.lock",
          content: fixture("javascript", "yarn_lockfiles", "wildcard.lock")
        )
      end
      let(:package2_npm_lock) do
        Dependabot::DependencyFile.new(
          name: "packages/package2/package-lock.json",
          content: fixture("javascript", "npm_lockfiles", "wildcard.json")
        )
      end
      let(:other_package_json) do
        Dependabot::DependencyFile.new(
          name: "packages/other_package/package.json",
          content:
            fixture("javascript", "package_files", "other_package.json")
        )
      end
      let(:other_package_yarn_lock) do
        Dependabot::DependencyFile.new(
          name: "packages/other_package/yarn.lock",
          content:
            fixture("javascript", "yarn_lockfiles", "other_package.lock")
        )
      end
      let(:other_package_npm_lock) do
        Dependabot::DependencyFile.new(
          name: "packages/other_package/package-lock.json",
          content:
            fixture("javascript", "npm_lockfiles", "other_package.json")
        )
      end

      let(:dependency_name) { "etag" }
      let(:version) { "1.8.1" }
      let(:previous_version) { "1.8.0" }
      let(:requirements) do
        [{
          requirement: "^1.1.0",
          file: "packages/package1/package.json",
          groups: ["devDependencies"],
          source: nil
        }, {
          requirement: "^1.0.0",
          file: "packages/other_package/package.json",
          groups: ["devDependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: "^1.1.0",
          file: "packages/package1/package.json",
          groups: ["devDependencies"],
          source: nil
        }, {
          requirement: "^1.0.0",
          file: "packages/other_package/package.json",
          groups: ["devDependencies"],
          source: nil
        }]
      end

      it "upates both lockfiles" do
        expect(updated_files.map(&:name)).
          to match_array(
            [
              "packages/package1/yarn.lock",
              "packages/package1/package-lock.json",
              "packages/other_package/yarn.lock",
              "packages/other_package/package-lock.json"
            ]
          )

        package1_yarn_lock =
          updated_files.find { |f| f.name == "packages/package1/yarn.lock" }
        package1_npm_lock =
          updated_files.
          find { |f| f.name == "packages/package1/package-lock.json" }
        parsed_package1_npm_lock = JSON.parse(package1_npm_lock.content)
        other_package_yarn_lock =
          updated_files.
          find { |f| f.name == "packages/other_package/yarn.lock" }
        other_package_npm_lock =
          updated_files.
          find { |f| f.name == "packages/other_package/package-lock.json" }
        parsed_other_pkg_npm_lock = JSON.parse(other_package_npm_lock.content)

        expect(package1_yarn_lock.content).
          to include("etag@^1.1.0:\n  version \"1.8.1\"")
        expect(other_package_yarn_lock.content).
          to include("etag@^1.0.0:\n  version \"1.8.1\"")

        expect(parsed_package1_npm_lock["dependencies"]["etag"]["version"]).
          to eq("1.8.1")
        expect(parsed_other_pkg_npm_lock["dependencies"]["etag"]["version"]).
          to eq("1.8.1")
      end
    end

    context "with a .npmrc" do
      let(:files) { [package_json, package_lock, npmrc] }

      context "that has an environment variable auth token" do
        let(:npmrc) do
          Dependabot::DependencyFile.new(
            name: ".npmrc",
            content: fixture("javascript", "npmrc", "env_auth_token")
          )
        end

        it "updates the files" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))
        end
      end

      context "that has an _auth line" do
        let(:npmrc) do
          Dependabot::DependencyFile.new(
            name: ".npmrc",
            content: fixture("javascript", "npmrc", "env_global_auth")
          )
        end

        let(:credentials) do
          [{
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org",
            "token" => "secret_token"
          }]
        end

        it "updates the files" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))
        end
      end

      context "that precludes updates to the lockfile" do
        let(:npmrc) do
          Dependabot::DependencyFile.new(
            name: ".npmrc",
            content: fixture("javascript", "npmrc", "no_lockfile")
          )
        end

        specify { expect(updated_files.map(&:name)).to eq(["package.json"]) }
      end
    end

    context "when a wildcard is specified" do
      let(:manifest_fixture_name) { "wildcard.json" }
      let(:yarn_lock_fixture_name) { "wildcard.lock" }

      let(:version) { "0.2.0" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "*",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) { requirements }

      it "only updates the lockfiles" do
        expect(updated_files.map(&:name)).
          to match_array(%w(yarn.lock package-lock.json))

        expect(updated_yarn_lock.content).
          to include("fetch-factory@*:\n  version \"0.2.0\"")
        expect(updated_npm_lock.content).
          to include("fetch-factory/-/fetch-factory-0.2.0.tgz")
      end
    end

    context "when the exact version we're updating from is still requested" do
      let(:files) { [package_json, yarn_lock] }
      let(:manifest_fixture_name) { "typedoc-plugin-ui-router.json" }
      let(:yarn_lock_fixture_name) { "typedoc-plugin-ui-router.lock" }

      let(:dependency_name) { "typescript" }
      let(:version) { "2.9.1" }
      let(:previous_version) { "2.1.4" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^2.1.1",
          groups: ["devDependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) { requirements }

      it "updates the lockfile" do
        expect(updated_files.map(&:name)).to eq(%w(yarn.lock))

        expect(updated_yarn_lock.content).
          to include("typescript@2.1.4:\n  version \"2.1.4\"")
        expect(updated_yarn_lock.content).
          to include("typescript@^2.1.1:\n  version \"2.9.1\"")
      end
    end

    describe "the updated package-lock.json" do
      it "has details of the updated item" do
        parsed_lockfile = JSON.parse(updated_npm_lock.content)
        expect(parsed_lockfile["dependencies"]["fetch-factory"]["version"]).
          to eq("0.0.2")
      end

      context "when the requirement has not been updated" do
        let(:requirements) { previous_requirements }

        it "has details of the updated item" do
          parsed_lockfile = JSON.parse(updated_npm_lock.content)
          expect(parsed_lockfile["dependencies"]["fetch-factory"]["version"]).
            to eq("0.0.2")

          expect(
            parsed_lockfile.dig(
              "dependencies", "fetch-factory", "requires", "es6-promise"
            )
          ).to eq("3.3.1")
        end

        context "for an npm6 lockfile" do
          let(:npm_lock_fixture_name) { "npm6.json" }

          it "has details of the updated item" do
            parsed_lockfile = JSON.parse(updated_npm_lock.content)
            expect(parsed_lockfile["dependencies"]["fetch-factory"]["version"]).
              to eq("0.0.2")

            expect(
              parsed_lockfile.dig(
                "dependencies", "fetch-factory", "requires", "es6-promise"
              )
            ).to eq("^3.0.2")
          end
        end
      end
    end

    describe "the updated yarn_lock" do
      it "has details of the updated item" do
        expect(updated_yarn_lock.content).to include("fetch-factory@^0.0.2")
      end

      context "when a dist-tag is specified" do
        let(:manifest_fixture_name) { "dist_tag.json" }
        let(:yarn_lock_fixture_name) { "dist_tag.lock" }

        let(:dependency_name) { "npm" }
        let(:version) { "5.9.0-next.0" }
        let(:previous_version) { "5.8.0" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "next",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) { requirements }

        it "has details of the updated item" do
          expect(updated_yarn_lock.content).to include("npm@next:")

          version =
            updated_yarn_lock.content.
            match(/npm@next:\n  version "(?<version>.*?)"/).
            named_captures["version"]

          expect(Dependabot::Utils::JavaScript::Version.new(version)).
            to be >= Dependabot::Utils::JavaScript::Version.new("5.9.0-next.0")
        end
      end

      context "when the version is missing from the lockfile" do
        let(:yarn_lock_fixture_name) { "missing_requirement.lock" }

        it "has details of the updated item (doesn't error)" do
          expect(updated_yarn_lock.content).to include("fetch-factory@^0.0.2")
        end
      end

      context "when updating only the lockfile" do
        let(:files) { [package_json, yarn_lock] }
        let(:manifest_fixture_name) { "lockfile_only_change.json" }
        let(:yarn_lock_fixture_name) { "lockfile_only_change.lock" }

        let(:dependency_name) { "babel-jest" }
        let(:version) { "22.4.3" }
        let(:previous_version) { "22.0.4" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^22.0.4",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) { requirements }

        it "has details of the updated item, but doesn't update everything" do
          # Updates the desired dependency
          expect(updated_yarn_lock.content).
            to include("babel-jest@^22.0.4:\n  version \"22.4.3\"")

          # Doesn't update unrelated dependencies
          expect(updated_yarn_lock.content).
            to include("eslint@^4.14.0:\n  version \"4.14.0\"")
        end
      end
    end

    ############################################################
    # Tests for error cases. Must test npm and Yarn separately #
    ############################################################
    describe "errors" do
      context "with a dependency version that can't be found" do
        let(:manifest_fixture_name) { "yanked_version.json" }
        let(:npm_lock_fixture_name) { "yanked_version.json" }
        let(:yarn_lock_fixture_name) { "yanked_version.lock" }

        context "with a yarn lockfile" do
          let(:files) { [package_json, yarn_lock] }
          it "raises a helpful error" do
            expect { updated_files }.
              to raise_error(Dependabot::DependencyFileNotResolvable)
          end

          context "when there is a private dep we don't have access to" do
            let(:manifest_fixture_name) { "private_source.json" }
            let(:yarn_lock_fixture_name) { "private_source.lock" }

            it "raises a helpful error" do
              # TODO: Raise custom error here
              expect { updater.updated_dependency_files }.
                to raise_error(Dependabot::DependencyFileNotResolvable)
            end
          end

          context "because we're updating to a non-existant version" do
            let(:yarn_lock_fixture_name) { "yarn.lock" }
            let(:npm_lock_fixture_name) { "package-lock.json" }
            let(:manifest_fixture_name) { "package.json" }

            let(:dependency_name) { "fetch-factory" }
            let(:version) { "5.0.2" }
            let(:requirements) do
              [{
                file: "package.json",
                requirement: "^5.0.2",
                groups: ["dependencies"],
                source: nil
              }]
            end

            it "raises an unhandled error" do
              expect { updated_files }.
                to raise_error(Dependabot::InconsistentRegistryResponse)
            end
          end
        end
      end

      context "with a dependency that can't be found" do
        let(:manifest_fixture_name) { "non_existant_dependency.json" }
        let(:npm_lock_fixture_name) { "yanked_version.json" }
        let(:yarn_lock_fixture_name) { "yanked_version.lock" }

        context "with an npm lockfile" do
          let(:files) { [package_json, package_lock] }
          it "raises a helpful error" do
            expect { updated_files }.
              to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
          end
        end

        context "with a yarn lockfile" do
          let(:files) { [package_json, yarn_lock] }
          it "raises a helpful error" do
            expect { updated_files }.
              to raise_error(Dependabot::DependencyFileNotResolvable)
          end
        end
      end

      context "with a git reference that Yarn would find but npm wouldn't" do
        let(:manifest_fixture_name) { "git_dependency_yarn_ref.json" }
        let(:npm_lock_fixture_name) { "git_dependency_yarn_ref.json" }

        context "with an npm lockfile" do
          let(:files) { [package_json, package_lock] }
          it "raises a helpful error" do
            expect { updated_files }.
              to raise_error(Dependabot::DependencyFileNotResolvable)
          end
        end
      end

      context "with a corrupted npm lockfile (version missing)" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "version_missing.json" }

        context "with an npm lockfile" do
          let(:files) { [package_json, package_lock] }
          it "raises a helpful error" do
            expect { updated_files }.
              to raise_error(Dependabot::DependencyFileNotResolvable)
          end
        end
      end

      context "with an unreachable git reference" do
        let(:npm_lock_fixture_name) { "git_dependency_bad_ref.json" }
        let(:manifest_fixture_name) { "git_dependency_bad_ref.json" }
        let(:yarn_lock_fixture_name) { "git_dependency_bad_ref.lock" }

        let(:dependency_name) { "lodash" }
        let(:version) { "1.3.1" }
        let(:previous_version) { "1.2.1" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        context "with an npm lockfile" do
          let(:files) { [package_json, package_lock] }
          it "raises a helpful error" do
            expect { updated_files }.to raise_error do |error|
              expect(error).to be_a(Dependabot::GitDependencyReferenceNotFound)
              expect(error.dependency).to eq("is-number")
            end
          end
        end
      end
    end

    ######################
    # npm specific tests #
    ######################
    describe "npm specific" do
      let(:files) { [package_json, package_lock] }

      context "when the package lock is empty" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "no_dependencies.json" }

        it "updates the files" do
          expect(updated_files.count).to eq(2)
        end
      end

      context "when the package lock has a numeric version for a git dep" do
        let(:manifest_fixture_name) { "git_dependency.json" }
        let(:npm_lock_fixture_name) { "git_dependency_version.json" }
        let(:dependency_name) { "is-number" }
        let(:requirements) do
          [{
            requirement: nil,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: "master"
            }
          }]
        end
        let(:previous_requirements) { requirements }
        let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
        let(:version) { "0c6b15a88bc10cd47f67a09506399dfc9ddc075d" }

        it "updates the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package-lock.json))

          parsed_package_lock = JSON.parse(updated_npm_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("git+https://github.com/jonschlinkert/is-number.git#"\
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end
      end
    end

    #######################
    # Yarn specific tests #
    #######################
    describe "Yarn specific" do
      let(:files) { [package_json, yarn_lock] }

      context "when a yarnrc would prevent updates to the yarn.lock" do
        let(:files) { [package_json, yarn_lock, yarnrc] }
        let(:yarnrc) do
          Dependabot::DependencyFile.new(
            name: ".yarnrc",
            content: "--frozen-lockfile true\n--install.frozen-lockfile true"
          )
        end

        it "updates the lockfile" do
          expect(updated_files.map(&:name)).to include("yarn.lock")
        end
      end

      context "when the lockfile needs to be cleaned up (Yarn bug)" do
        let(:manifest_fixture_name) { "no_lockfile_change.json" }
        let(:yarn_lock_fixture_name) { "no_lockfile_change.lock" }

        let(:dependency_name) { "babel-register" }
        let(:version) { "6.26.0" }
        let(:previous_version) { "6.24.1" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^6.26.0",
            groups: ["devDependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^6.24.1",
            groups: ["devDependencies"],
            source: nil
          }]
        end

        it "removes details of the old version" do
          expect(updated_yarn_lock.content).
            to_not include("babel-register@^6.24.1:")
          expect(updated_yarn_lock.content).
            to_not include("integrity sha512-")
        end
      end

      context "with a sub-dependency" do
        let(:manifest_fixture_name) { "no_lockfile_change.json" }
        let(:yarn_lock_fixture_name) { "no_lockfile_change.lock" }

        let(:dependency_name) { "acorn" }
        let(:version) { "5.7.3" }
        let(:previous_version) { "5.1.1" }
        let(:requirements) { [] }
        let(:previous_requirements) { [] }

        it "updates the version" do
          expect(updated_yarn_lock.content).
            to include(%(acorn@^5.0.0, acorn@^5.1.2:\n  version "5.7.3"))
        end
      end

      context "with resolutions" do
        let(:manifest_fixture_name) { "resolution_specified.json" }
        let(:yarn_lock_fixture_name) { "resolution_specified.lock" }

        let(:dependency_name) { "lodash" }
        let(:version) { "3.10.1" }
        let(:previous_version) { "3.10.0" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^3.0",
            groups: ["devDependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) { requirements }

        it "updates the resolution, as well as the declaration" do
          expect(updated_package_json.content).
            to include('"lodash": "3.10.1"')

          expect(updated_yarn_lock.content).
            to include("lodash@2.4.1, lodash@3.10.1, lodash@^3.0, "\
                       "lodash@^3.10.1:\n  version \"3.10.1\"")
        end
      end

      context "with workspaces" do
        let(:files) { [package_json, yarn_lock, package1, other_package] }
        let(:manifest_fixture_name) { "workspaces.json" }
        let(:yarn_lock_fixture_name) { "workspaces.lock" }
        let(:package1) do
          Dependabot::DependencyFile.new(
            name: "packages/package1/package.json",
            content: fixture("javascript", "package_files", "package1.json")
          )
        end
        let(:other_package) do
          Dependabot::DependencyFile.new(
            name: "other_package/package.json",
            content:
              fixture("javascript", "package_files", "other_package.json")
          )
        end

        let(:dependency_name) { "lodash" }
        let(:version) { "1.3.1" }
        let(:previous_version) { "1.2.0" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "1.3.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "packages/package1/package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "other_package/package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "1.2.0",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "packages/package1/package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "other_package/package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "updates the yarn.lock and all three package.jsons" do
          lockfile = updated_files.find { |f| f.name == "yarn.lock" }
          package = updated_files.find { |f| f.name == "package.json" }
          package1 = updated_files.find do |f|
            f.name == "packages/package1/package.json"
          end
          other_package = updated_files.find do |f|
            f.name == "other_package/package.json"
          end

          expect(lockfile.content).to include("lodash@1.3.1, lodash@^1.3.1:")
          expect(lockfile.content).to_not include("lodash@^1.2.1:")
          expect(lockfile.content).to_not include("workspace-aggregator")

          expect(package.content).to include("\"lodash\": \"1.3.1\"")
          expect(package.content).to include("\"./packages/*\",\n")
          expect(package1.content).to include("\"lodash\": \"^1.3.1\"")
          expect(other_package.content).to include("\"lodash\": \"^1.3.1\"")
        end

        context "with a dependency that doesn't appear in all the workspaces" do
          let(:dependency_name) { "chalk" }
          let(:version) { "0.4.0" }
          let(:previous_version) { "0.3.0" }
          let(:requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "0.4.0",
              groups: ["dependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "0.3.0",
              groups: ["dependencies"],
              source: nil
            }]
          end

          it "updates the yarn.lock and the correct package_json" do
            expect(updated_files.map(&:name)).
              to match_array(%w(yarn.lock packages/package1/package.json))

            lockfile = updated_files.find { |f| f.name == "yarn.lock" }
            expect(lockfile.content).to include("chalk@0.4.0:")
            expect(lockfile.content).to_not include("workspace-aggregator")
          end
        end

        context "when the package.json doesn't specify that it's private" do
          let(:manifest_fixture_name) { "workspaces_bad.json" }

          it "raises a helpful error" do
            expect { updater.updated_dependency_files }.
              to raise_error(Dependabot::DependencyFileNotEvaluatable)
          end
        end

        context "with a dependency that appears as a development dependency" do
          let(:dependency_name) { "etag" }
          let(:version) { "1.8.1" }
          let(:previous_version) { "1.8.0" }
          let(:requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "^1.8.1",
              groups: ["devDependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "packages/package1/package.json",
              requirement: "^1.1.0",
              groups: ["devDependencies"],
              source: nil
            }]
          end

          it "updates the right file" do
            expect(updated_files.map(&:name)).
              to match_array(%w(yarn.lock packages/package1/package.json))
          end

          it "updates the existing development declaration" do
            file = updated_files.find do |f|
              f.name == "packages/package1/package.json"
            end
            parsed_file = JSON.parse(file.content)
            expect(parsed_file.dig("dependencies", "etag")).to be_nil
            expect(parsed_file.dig("devDependencies", "etag")).to eq("^1.8.1")
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative "lib/kozeki/aws/version"

Gem::Specification.new do |spec|
  spec.name = "kozeki-aws"
  spec.version = Kozeki::Aws::VERSION
  spec.authors = ["Sorah Fukumori"]
  spec.email = ["her@sorah.jp"]

  spec.summary = "AWS plugins for Kozeki"
  spec.homepage = "https://github.com/sorah/kozeki"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "scripts"
  spec.executables = spec.files.grep(%r{\Ascripts/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "kozeki"
  spec.add_dependency "aws-sdk-s3"
end

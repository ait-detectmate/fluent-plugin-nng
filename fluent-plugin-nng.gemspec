lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name    = 'fluent-plugin-nng'
  spec.version = '1.0.1'
  spec.authors = ['whotwagner']
  spec.email   = ['code@feedyourhead.at']

  spec.summary       = %q{Fluentd input-/output plugin for nanomsg-ng.}
  spec.description   = %q{Fluentd input-/output plugin for nanomsg-ng.}
  spec.homepage      = "https://github.com/ait-detectmate/fluent-plugin-nng"
  spec.license       = "EUPL-1.2"

  spec.files         = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency 'bundler', '~> 2.6.9'
  spec.add_development_dependency 'rake', '~> 13.3.1'
  spec.add_development_dependency 'test-unit', '~> 3.6.7'
  spec.add_runtime_dependency 'nng', '~> 1.0.1'
  spec.add_runtime_dependency "fluentd", [">= 0.14.10", "< 2"]
end

# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.name          = "fluent-plugin-out-http-streaming"
  gem.version       = "0.1.6"
  gem.authors       = ["Marica Odagaki", "Garrett Serack"]
  gem.email         = ["ento.entotto@gmail.com", "garretts@microsoft.com"]
  gem.summary       = %q{A generic Fluentd output plugin to send logs to an HTTP endpoint with streaming}
  gem.description   = %q{A generic Fluentd output plugin to send logs to an HTTP endpoint (streaming)}
  gem.homepage      = "https://github.com/ento/fluent-plugin-out-http"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.licenses      = ["Apache"]

  gem.add_runtime_dependency 'yajl-ruby', '~> 1.0'
  gem.add_runtime_dependency 'fluentd', '~> 0.12', '>= 0.12.0'
  gem.add_development_dependency 'bundler', '~> 0'
  gem.add_development_dependency "rake" , '~> 0'
end

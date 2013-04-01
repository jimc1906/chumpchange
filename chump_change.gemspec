# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "chump_change/version"

Gem::Specification.new do |s|
  s.name        = "chump_change"
  s.version     = ChumpChange::VERSION
  s.authors     = ["Jim Clingenpeel"]
  s.email       = "jclingen@nearinfinity.com"
  s.homepage    = "https://github.com/jimc1906/chumpchange"
  s.summary     = %q{Provide DSL to control ability to save changes to attributes}
  s.description = %q{DSL may be used to allow changes to model attributes based on the value of a driver attribute}

  s.rubyforge_project = "chump_change"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency("rspec",    "~> 2.13.0")
  s.add_development_dependency("activerecord",    "~> 3.2.9")
  s.add_development_dependency("sqlite3")
  s.add_development_dependency("debugger")
end

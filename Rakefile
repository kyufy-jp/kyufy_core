require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

require "bundler/gem_tasks"

# Regenerate the language-neutral exports under data/ (schema: data/README.md). Run this after
# editing Geo's tables or db/seeds/programs/*.yml — test/kyufy_core/data_export_test.rb fails
# when the committed files drift from their sources.
namespace :data do
  desc "Regenerate data/*.json from KyufyCore::Geo and db/seeds/programs/*.yml"
  task :export do
    require_relative "lib/kyufy_core/data_export"
    KyufyCore::DataExport.write_all.each { |path| puts "wrote #{path.delete_prefix("#{Dir.pwd}/")}" }
  end
end

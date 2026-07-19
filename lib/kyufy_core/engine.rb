require "prefixed_ids"
require "neighbor"

module KyufyCore
  class Engine < ::Rails::Engine
    isolate_namespace KyufyCore

    # Host apps install this engine's migrations the standard way:
    #   bin/rails kyufy_core:install:migrations
    # (The bundled test/dummy app points its db/migrate path straight at the engine's migrate
    # dir, so it needs no copy — see test/dummy/config/application.rb.)
  end
end

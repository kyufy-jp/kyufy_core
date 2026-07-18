# Loads the packaged Tokyo seed (§11) via ManualYamlAdapter -> Importer, so the engine demos
# standalone in the dummy host (no Jumpstart Pro needed).
KyufyCore.import_yaml
puts "Seeded #{KyufyCore::Program.count} program(s), #{KyufyCore::Requirement.count} requirement(s)."

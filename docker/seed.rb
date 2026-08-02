# Load the packaged real-program seed, but only into an empty database: KyufyCore.import_dir
# always create!s, so re-running it on a warm volume would duplicate every program (README
# "Seed data"). Run via `bin/rails runner docker/seed.rb` from docker/entrypoint.sh.
existing = KyufyCore::Program.count

if existing.positive?
  puts "==> #{existing} programs already present; skipping import"
else
  programs = KyufyCore.import_dir
  puts "==> imported #{programs.size} programs / #{KyufyCore::Requirement.count} requirements"
end

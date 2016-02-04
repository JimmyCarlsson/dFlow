namespace :app_config do
  desc "Generates a .yml file with the complete contents of all app-config files"
  $rails_rake_task = true
  $do_not_load_config = true
  task generate_file: :environment do
    ConfigLoader.generate_file(base_file_path: "#{Rails.root}/config/app-config.yml")
  end

end

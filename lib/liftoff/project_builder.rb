require 'fileutils'
require 'xcodeproj'
require 'erb'

module Liftoff
  class ProjectBuilder

    def initialize(project_config)
      @project_config = project_config
    end

    def create_project
      xcode_project.root_object.attributes['CLASSPREFIX'] = @project_config.prefix
      xcode_project.root_object.attributes['ORGANIZATIONNAME'] = @project_config.company

      @project_config.directories.each do |directory|
        create_tree(directory)
      end

      xcode_project.save
    end

    private

    def app_target
      @app_target ||= xcode_project.new_target(:application, @project_config.name, :ios, 7.0)
    end

    def create_tree(tree, path = [], parent_group = xcode_project)
      if tree.class == String
        mkdir_gitkeep(path)
        move_template(path, tree)
        link_file(tree, parent_group, path)
        return
      end

      tree.each_pair do |raw_directory, child|
        directory = rendered_string(raw_directory)
        path += [directory]
        mkdir_gitkeep(path)
        created_group = create_group(directory, parent_group)
        if child
          child.each do |c|
            create_tree(c, path, created_group)
          end
        end
      end
    end

    def mkdir_gitkeep(path)
      dir_path = File.join(*path)
      FileUtils.mkdir_p(dir_path)
      FileUtils.touch(File.join(dir_path, '.gitkeep'))
    end

    def create_group(name, parent_group)
      parent_group.new_group(name, name)
    end

    def move_template(path, raw_template_name)
      rendered_template_name = rendered_string(raw_template_name)
      destination_template_path = File.join(*path, rendered_template_name)
      FileManager.new.generate(raw_template_name, destination_template_path, @project_config)
    end

    def link_file(raw_template_name, parent_group, path)
      rendered_template_name = rendered_string(raw_template_name)
      file = parent_group.new_file(rendered_template_name)
      unless rendered_template_name.end_with?('h', 'plist')
        app_target.add_file_references([file])
      end

      if rendered_template_name.end_with?('plist')
        app_target.build_configurations.each do |configuration|
          configuration.build_settings['INFOPLIST_FILE'] = File.join(*path, rendered_template_name)
        end
      elsif rendered_template_name.end_with?('pch')
        app_target.build_configurations.each do |configuration|
          configuration.build_settings['GCC_PREFIX_HEADER'] = File.join(*path, rendered_template_name)
        end
      end
    end

    def xcode_project
      path = Pathname.new("#{@project_config.name}.xcodeproj").expand_path
      @project ||= Xcodeproj::Project.new(path)
    end

    def rendered_string(raw_string)
      ERB.new(raw_string).result(@project_config.get_binding)
    end
  end
end

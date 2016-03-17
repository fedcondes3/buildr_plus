#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

BuildrPlus::FeatureManager.feature(:roles) do |f|
  f.enhance(:Config) do

    class ProjectDescription < BuildrPlus::BaseElement
      def initialize(name, options = {}, &block)
        @name = name
        super(options, &block)
      end

      attr_reader :name
      attr_accessor :description
      attr_accessor :parent
      attr_writer :template

      def template?
        !!@template
      end

      def roles
        @roles ||= []
      end

      def roles=(roles)
        @roles = roles
      end

      def in_role?(role)
        roles.any? { |r| r.to_s == role.to_s }
      end

      def customize(&block)
        customization_map << block
      end

      def customizations
        customization_map.dup
      end

      protected

      def customization_map
        @customizations ||= []
      end
    end

    def role(name, options = {}, &block)
      role = role_map[name.to_s]
      if role.nil? || options[:replace]
        role = []
        role_map[name.to_s] = role
      end
      role << block
      nil
    end

    def role_by_name(name)
      role_map[name.to_s]
    end

    def roles
      role_map.dup
    end

    def buildr_project_with_role(role)
      project = buildr_projects_with_role(role)[0]
      raise "Unable to locate project with role #{role}" unless project
      project
    end

    def buildr_projects_with_role(role)
      projects = projects_with_role(role).collect { |p| p.name }
      buildr_projects = Buildr.projects(:no_invoke => true).
        select { |project| projects.include?(project.name.gsub(/^[^:]*\:/, '')) }
      buildr_projects.each{|p|p.invoke}
      buildr_projects
    end

    def merge_projects_with_role(target, role)
      BuildrPlus::Roles.buildr_projects_with_role(role).each do |dep|
        target.with dep.package(:jar),
                    dep.compile.dependencies
      end
    end

    def project(name, options = {}, &block)
      project = project_map[name.to_s]
      unless project
        project = ProjectDescription.new(name, options)
        project_map[name.to_s] = project
      end
      project.customize(&block) if block_given?
      project
    end

    def project_by_name(name)
      project_map[name.to_s]
    end

    def projects
      project_map.values.dup
    end

    def project_with_role(role)
      project = projects_with_role(role)[0]
      raise "Unable to locate project with role #{role}" unless project
      project
    end

    def project_with_role?(role)
      projects_with_role(role).size > 0
    end

    def projects_with_role(role)
      project_map.values.select { |project| project.in_role?(role) }
    end

    def match_project
      project.name.gsub(/^[^:]*\:/, '')
    end

    def define_top_level_projects
      BuildrPlus::Roles.projects.select { |p| !p.template? }.each do |p|
        Buildr.class_eval do
          define p.name.to_s do
            project.apply_roles!
          end
        end
      end
    end

    protected

    def project_map
      @project_map ||= {}
    end

    def role_map
      @role_map ||= {}
    end
  end

  f.enhance(:ProjectExtension) do

    def descriptor=(descriptor)
      @descriptor = descriptor
    end

    def descriptor
      @descriptor || (raise "descriptor invoked on #{project.name} when not yet set")
    end

    def roles
      descriptor.roles
    end

    def roles=(roles)
      descriptor.roles = roles
    end

    def in_role?(role)
      descriptor.in_role?(role)
    end

    def apply_roles?
      @apply_roles.nil? ? true : !!@apply_roles
    end

    attr_writer :apply_roles

    def apply_roles!
      if apply_roles?
        BuildrPlus::Roles.projects.each do |p|
          if p.parent && project.descriptor.in_role?(p.parent)
            instance_eval do
              desc p.description if p.description
              define p.name do
              end
            end
          end
        end
        project.descriptor.customizations.each do |customization|
          instance_eval &customization
        end
        project.roles.each do |role_name|
          role = BuildrPlus::Roles.role_by_name(role_name)
          raise "Unknown role #{role_name} declared on project #{project.name}" unless role
          role.each do |r|
            instance_eval &r
          end
        end

        BuildrPlus::Roles.projects.each do |p|
          if p.parent && project.descriptor.in_role?(p.parent)
            instance_eval do
              project(p.name).instance_eval do
                project.apply_roles!
              end
            end
          end
        end
      end
    end

    before_define do |project|
      project.descriptor = BuildrPlus::Roles.project(project.name.gsub(/^[^:]*\:/, ''))
    end
  end
end

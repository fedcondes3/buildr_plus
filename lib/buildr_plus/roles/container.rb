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

BuildrPlus::Roles.role(:container) do

  if BuildrPlus::FeatureManager.activated?(:domgen)
    generators = []

    generators << [:redfish_fragment] if BuildrPlus::FeatureManager.activated?(:redfish)
    generators << [:keycloak_client_config] if BuildrPlus::FeatureManager.activated?(:keycloak)

    generators += project.additional_domgen_generators

    Domgen::Build.define_generate_task(generators.flatten, :buildr_project => project) do |t|
      t.filter = project.domgen_filter
    end unless generators.empty?
  end

  project.publish = false

  BuildrPlus::Roles.projects.each do |p|
    other = project.project(p.name)
    unless other.test.compile.sources.empty? || !other.iml?
      other.idea_testng_configuration_created = true
      ipr.add_testng_configuration(p.name.to_s,
                                   :module => other.iml.name,
                                   :jvm_args => BuildrPlus::Testng.default_testng_args(project,p).join(' '))
    end
  end

  # Need to use definitions as projects have yet to be when resolving
  # container project which is typically the root project
  if BuildrPlus::Roles.project_with_role?(:server)
    server_project = project(BuildrPlus::Roles.project_with_role(:server).name)
    model_project =
      BuildrPlus::Roles.project_with_role?(:model) ?
        project(BuildrPlus::Roles.project_with_role(:model).name) :
        nil
    shared_project =
      BuildrPlus::Roles.project_with_role?(:shared) ?
        project(BuildrPlus::Roles.project_with_role(:shared).name) :
        nil

    dependencies = [server_project, model_project, shared_project].compact
    # Spotbugs+jetbrains libs added otherwise CDI scanning slows down due to massive number of ClassNotFoundExceptions
    dependencies << BuildrPlus::Deps.spotbugs_provided
    dependencies << BuildrPlus::Deps.jetbrains_annotations
    dependencies << BuildrPlus::Deps.server_compile_deps

    war_module_names = [server_project.iml.name]
    jpa_module_names = []
    jpa_module_names << model_project.iml.name if model_project

    ejb_module_names = [server_project.iml.name]
    ejb_module_names << model_project.iml.name if model_project

    exploded_war_name = "#{project.iml.id}-exploded"
    ipr.add_exploded_war_artifact(project,
                                  :name => exploded_war_name,
                                  :dependencies => dependencies,
                                  :war_module_names => war_module_names,
                                  :jpa_module_names => jpa_module_names,
                                  :ejb_module_names => ejb_module_names)

    war_name = "#{project.iml.id}-archive"
    ipr.add_war_artifact(project,
                         :name => war_name,
                         :dependencies => dependencies,
                         :war_module_names => war_module_names,
                         :jpa_module_names => jpa_module_names,
                         :ejb_module_names => ejb_module_names)

    remote_packaged_apps = BuildrPlus::Glassfish.remote_only_packaged_apps.dup.merge(BuildrPlus::Glassfish.packaged_apps)
    local_packaged_apps = BuildrPlus::Glassfish.non_remote_only_packaged_apps.dup.merge(BuildrPlus::Glassfish.packaged_apps)

    local_packaged_apps['greenmail'] = BuildrPlus::Libs.greenmail_server if BuildrPlus::FeatureManager.activated?(:mail)

    ipr.add_glassfish_remote_configuration(project,
                                           :server_name => 'GlassFish 5.194.0',
                                           :artifacts => {war_name => project.iml.id},
                                           :packaged => remote_packaged_apps)
    unless BuildrPlus::Redfish.local_domain_update_only?
      ipr.add_glassfish_configuration(project,
                                      :server_name => 'GlassFish 5.194.0',
                                      :exploded => {exploded_war_name => project.iml.id},
                                      :packaged => local_packaged_apps)

      if local_packaged_apps.size > 0
        only_packaged_apps = BuildrPlus::Glassfish.only_only_packaged_apps.dup
        ipr.add_glassfish_configuration(project,
                                        :configuration_name => "#{Reality::Naming.pascal_case(project.name)} Only - GlassFish 5.194.0",
                                        :server_name => 'GlassFish 5.194.0',
                                        :exploded => {exploded_war_name => project.iml.id},
                                        :packaged => only_packaged_apps)
      end
    end

    iml.excluded_directories << project._('tmp')

    BuildrPlus::Roles.buildr_projects_with_role(:user_experience).each do |p|
      gwt_modules = p.determine_top_level_gwt_modules('Dev')
      gwt_modules.each do |gwt_module|
        short_name = gwt_module.gsub(/.*\.([^.]+)Dev$/, '\1')
        path = short_name.gsub(/^#{Reality::Naming.pascal_case(project.name)}/, '')
        if path.size > 0
          server_project = project(BuildrPlus::Roles.project_with_role(:server).name)
          %w(html jsp).each do |extension|
            candidate = "#{Reality::Naming.underscore(path)}.#{extension}"
            path = candidate if File.exist?(server_project._(:source, :main, :webapp_local, candidate))
          end
        end
        ipr.add_gwt_configuration(p,
                                  :gwt_module => gwt_module,
                                  :start_javascript_debugger => false,
                                  :open_in_browser => false,
                                  :vm_parameters => '-Xmx3G',
                                  :shell_parameters => "#{BuildrPlus::Gwt.enable_gwt_js_exports? ? '-generateJsInteropExports ' : ''}-codeServerPort 8889 -bindAddress 0.0.0.0 -deploy #{_(:generated, :gwt, 'deploy')} -extra #{_(:generated, :gwt, 'extra')} -war #{_(:generated, :gwt, 'war')} -style PRETTY -XmethodNameDisplayMode FULL -incremental -logLevel INFO -strict -nostartServer",
                                  :launch_page => "http://127.0.0.1:8080/#{p.root_project.name}/#{path}")
      end
    end
  end
end

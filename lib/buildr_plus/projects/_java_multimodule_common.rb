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

require 'buildr_plus/projects/_java'

base_directory = File.dirname(Buildr.application.buildfile.to_s)

BuildrPlus::FeatureManager.activate_features([:less]) if File.exist?("#{base_directory}/server/#{BuildrPlus::Less.default_less_path}")

if File.exist?("#{base_directory}/replicant-shared")
  BuildrPlus::Roles.project('replicant-shared', :roles => [:replicant_shared], :parent => :container, :template => true, :description => 'Shared Replicant Components')
  BuildrPlus::Roles.project('replicant-qa-support', :roles => [:replicant_qa_support], :parent => :container, :template => true, :description => 'Shared Replicant Test Infrastructure')
end

if File.exist?("#{base_directory}/replicant-ee-client")
  BuildrPlus::Roles.project('replicant-ee-client', :roles => [:replicant_ee_client], :parent => :container, :template => true, :description => 'Shared EE Client')
end

if File.exist?("#{base_directory}/shared")
  BuildrPlus::Roles.project('shared', :roles => [:shared], :parent => :container, :template => true, :description => 'Shared Components')
end

if File.exist?("#{base_directory}/model") || File.exist?("#{base_directory}/model-qa-support") || BuildrPlus::FeatureManager.activated?(:domgen)
  BuildrPlus::Roles.project('model', :roles => [:model], :parent => :container, :template => true, :description => 'Persistent Entities, Messages and Data Structures')
  if BuildrPlus::FeatureManager.activated?(:sync) && !BuildrPlus::Sync.standalone?
    BuildrPlus::Roles.project('sync_model', :roles => [:sync_model], :parent => :container, :template => true, :description => 'Shared Model used to write External synchronization services')
  end
  BuildrPlus::Roles.project('model-qa-support', :roles => [:model_qa_support], :parent => :container, :template => true, :description => 'Model Test Infrastructure')
end

if File.exist?("#{base_directory}/gwt")
  BuildrPlus::Roles.project('gwt', :roles => [:gwt], :parent => :container, :template => true, :description => 'GWT Library')
  BuildrPlus::Roles.project('gwt-qa-support', :roles => [:gwt_qa_support], :parent => :container, :template => true, :description => 'GWT Test Infrastructure')
  BuildrPlus::FeatureManager.activate_features([:jackson]) unless BuildrPlus::FeatureManager.activated?(:jackson)
end

if BuildrPlus::FeatureManager.activated?(:soap) || File.exist?("#{base_directory}/replicant-ee-client")
  BuildrPlus::Roles.project('soap-client', :roles => [:soap_client], :parent => :container, :template => true, :description => 'SOAP Client API')
  BuildrPlus::Roles.project('soap-qa-support', :roles => [:soap_qa_support], :parent => :container, :template => true, :description => 'SOAP Test Infrastructure')
end

if File.exist?("#{base_directory}/integration-qa-support")
  BuildrPlus::Roles.project('integration-qa-support', :roles => [:integration_qa_support], :parent => :container, :template => true, :description => 'Integration Test Infrastructure')
  BuildrPlus::Roles.project('integration-tests', :roles => [:integration_tests], :parent => :container, :template => true, :description => 'Integration Tests')
end

BuildrPlus::Roles.default_role = :container

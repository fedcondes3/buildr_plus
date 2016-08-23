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

# Enable this feature if the code is tested using travis
BuildrPlus::FeatureManager.feature(:jenkins) do |f|
  f.enhance(:Config) do
    def jenkins_build_scripts
      (@jenkins_build_scripts ||= standard_build_scripts).dup
    end

    def publish_task_type=(publish_task_type)
      raise "Can not set publish task type to #{publish_task_type.inspect} as not one of expected values" unless [:oss, :external, :none].include?(publish_task_type)
      @publish_task_type = publish_task_type
    end

    def publish_task_type
      return @publish_task_type unless @publish_task_type.nil?
      return :oss if BuildrPlus::FeatureManager.activated?(:oss)
      :none
    end

    def skip_stage?(stage)
      skip_stage_list.include?(stage)
    end

    def skip_stage!(stage)
      skip_stage_list << stage
    end

    def skip_stages
      skip_stage_list.dup
    end

    def add_ci_task(key, label, task, pre_script = nil)
      additional_tasks[".jenkins/#{key}.groovy"] = buildr_task_content(label, task, pre_script)
    end

    def add_pre_package_buildr_stage(label, buildr_task)
      pre_package_stages[label] = "  #{buildr_command(buildr_task)}"
    end

    def add_post_package_buildr_stage(label, buildr_task)
      post_package_stages[label] = "  #{buildr_command(buildr_task)}"
    end

    def add_post_import_buildr_stage(label, buildr_task)
      post_import_stages[label] = "  #{buildr_command(buildr_task)}"
    end

    private

    def skip_stage_list
      @skip_stages ||= []
    end

    def pre_package_stages
      @pre_package_stages ||= {}
    end

    def post_package_stages
      @post_package_stages ||= {}
    end

    def post_import_stages
      @post_import_stages ||= {}
    end

    def additional_tasks
      @additional_scripts ||= {}
    end

    def standard_build_scripts
      scripts =
        {
          'Jenkinsfile' => jenkinsfile_content,
          '.jenkins/main.groovy' => main_content(Buildr.projects[0].root_project),
        }
      scripts['.jenkins/publish.groovy'] = publish_content(self.publish_task_type == :oss) unless self.publish_task_type == :none
      scripts.merge!(additional_tasks)
      scripts
    end

    def publish_content(oss)
      pre_script = <<PRE
export DOWNLOAD_REPO=${env.UPLOAD_REPO}
export UPLOAD_REPO=${env.EXTERNAL_#{oss ? 'OSS_' : ''}UPLOAD_REPO}
export UPLOAD_USER=${env.EXTERNAL_#{oss ? 'OSS_' : ''}UPLOAD_USER}
export UPLOAD_PASSWORD=${env.EXTERNAL_#{oss ? 'OSS_' : ''}UPLOAD_PASSWORD}
export PUBLISH_VERSION=${PUBLISH_VERSION}
PRE
      buildr_task_content('Publish', 'ci:publish', pre_script)
    end

    def buildr_task_content(label, task, pre_script)
      content = <<CONTENT
#{prepare_content(false)}
  stage '#{label}'
  #{buildr_command(task, :pre_script => pre_script)}
CONTENT
      inside_node(inside_docker_image(content))
    end

    def jenkinsfile_content
      inside_node("  checkout scm\n  load '.jenkins/main.groovy'")
    end

    def prepare_content(include_artifacts)
      content = <<CONTENT
  stage 'Prepare'
  checkout scm
  retry(8) {
    #{shell_command('gem install bundler')}
  }
  retry(8) {
    #{shell_command('bundle install --deployment')}
  }
CONTENT
      if include_artifacts
        content += <<CONTENT
  retry(8) {
    #{buildr_command('artifacts')}
  }
CONTENT
      end
      content
    end

    def main_content(root_project)
      content = "#{prepare_content(true)}\n"

      unless skip_stage?('Commit')
        content += <<CONTENT
  stage 'Commit'
  #{buildr_command('ci:commit')}
CONTENT

        if BuildrPlus::FeatureManager.activated?(:checkstyle)
          content += <<CONTENT
  step([$class: 'hudson.plugins.checkstyle.CheckStylePublisher', pattern: 'reports/#{root_project.name}/checkstyle/checkstyle.xml'])
  publishHTML(target: [allowMissing: false, alwaysLinkToLastBuild: false, keepAll: true, reportDir: 'reports/#{root_project.name}/checkstyle', reportFiles: 'checkstyle.html', reportName: 'Checkstyle issues'])
CONTENT
        end
        if BuildrPlus::FeatureManager.activated?(:findbugs)
          content += <<CONTENT
  step([$class: 'FindBugsPublisher', pattern: 'reports/#{root_project.name}/findbugs/findbugs.xml', unstableTotalAll: '1', failedTotalAll: '1', isRankActivated: true, canComputeNew: true, shouldDetectModules: false, useDeltaValues: false, canRunOnFailed: false, thresholdLimit: 'low'])
  publishHTML(target: [allowMissing: false, alwaysLinkToLastBuild: false, keepAll: true, reportDir: 'reports/#{root_project.name}/findbugs', reportFiles: 'findbugs.html', reportName: 'Findbugs issues'])
CONTENT
        end
        if BuildrPlus::FeatureManager.activated?(:pmd)
          content += <<CONTENT
  step([$class: 'PmdPublisher', pattern: 'reports/#{root_project.name}/pmd/pmd.xml'])
  publishHTML(target: [allowMissing: false, alwaysLinkToLastBuild: false, keepAll: true, reportDir: 'reports/#{root_project.name}/pmd/', reportFiles: 'pmd.html', reportName: 'PMD Issues'])
CONTENT
        end
        if BuildrPlus::FeatureManager.activated?(:jdepend)
          content += <<CONTENT
  publishHTML(target: [allowMissing: false, alwaysLinkToLastBuild: false, keepAll: true, reportDir: 'reports/#{root_project.name}/jdepend', reportFiles: 'jdepend.html', reportName: 'JDepend Report'])
CONTENT
        end
      end

      pre_package_stages.each do |label, stage_content|
        content += <<CONTENT

  stage '#{label}'
#{stage_content}
CONTENT
      end

      unless skip_stage?('Package')
        content += <<CONTENT

  stage 'Package'
  #{buildr_command('ci:package')}
CONTENT
        if BuildrPlus::FeatureManager.activated?(:testng)
          content += <<CONTENT

  step([$class: 'hudson.plugins.testng.Publisher', reportFilenamePattern: 'reports/*/testng/testng-results.xml'])
CONTENT
        end
      end

      unless skip_stage?('Package Pg')
        if BuildrPlus::FeatureManager.activated?(:db) && BuildrPlus::Db.is_multi_database_project?
          content += <<CONTENT

  stage 'Package Pg'
  #{buildr_command('ci:package_no_test', :pre_script => "export DB_TYPE=pg\nexport TEST=no")}
CONTENT
        end
      end

      post_package_stages.each do |label, stage_content|
        content += <<CONTENT

  stage '#{label}'
#{stage_content}
CONTENT
      end

      if BuildrPlus::FeatureManager.activated?(:dbt) &&
        ::Dbt.database_for_key?(:default) &&
        BuildrPlus::Dbt.database_import?(:default)
        unless skip_stage?('DB Import')
          content += <<CONTENT

  stage 'DB Import'
  #{shell_command('xvfb-run -a bundle exec buildr ci:import')}
CONTENT
          #TODO: Collect tests for iris that runs tests after import
          if BuildrPlus::FeatureManager.activated?(:testng) && false
            content += <<CONTENT

  step([$class: 'hudson.plugins.testng.Publisher', reportFilenamePattern: 'reports/*/testng/testng-results.xml'])
CONTENT
          end
        end

        BuildrPlus::Ci.additional_import_tasks.each do |import_variant|
          unless skip_stage?("DB #{import_variant} Import")
            content += <<CONTENT

  stage 'DB #{import_variant} Import'
  #{buildr_command("ci:import:#{import_variant}")}
CONTENT
          end
        end
      end

      post_import_stages.each do |label, stage_content|
        content += <<CONTENT

  stage '#{label}'
#{stage_content}
CONTENT
      end

      inside_docker_image(content)
    end

    def buildr_command(args, options = {})
      shell_command("xvfb-run -a bundle exec buildr #{args}", options)
    end

    def shell_command(command, options = {})
      pre_script = options[:pre_script] ? "#{options[:pre_script]}\n" : ''
      "sh \"\"\"\n#{standard_command_env}\n#{pre_script}#{command}\n\"\"\""
    end

    def inside_node(content)
      <<CONTENT
node {
#{content}
}
CONTENT
    end

    def inside_docker_image(content)
      java_version = BuildrPlus::Java.version == 7 ? 'java-7.80.15' : 'java-8.92.14'
      ruby_version = "#{BuildrPlus::Ruby.ruby_version =~ /jruby/ ? '' : 'ruby-'}#{BuildrPlus::Ruby.ruby_version}"

      <<CONTENT
docker.image('stocksoftware/build:#{java_version}_#{ruby_version}').inside {
#{content}
}
CONTENT
    end

    def standard_command_env
      env = <<-SH
export PRODUCT_VERSION=${env.BUILD_NUMBER}-`git rev-parse --short HEAD`
export GEM_HOME=`pwd`/.gems;
export GEM_PATH=`pwd`/.gems;
export M2_REPO=`pwd`/.repo;
export PATH=\\${PATH}:\\${GEM_PATH}/bin;
      SH
      if BuildrPlus::FeatureManager.activated?(:docker)
        env += <<-SH
export DOCKER_TLS_VERIFY=${env.DOCKER_TLS_VERIFY};
export DOCKER_HOST=${env.DOCKER_HOST}
export DOCKER_CERT_PATH=${env.DOCKER_CERT_PATH}
        SH
      end
      env
    end
  end
  f.enhance(:ProjectExtension) do
    task 'jenkins:check' do
      base_directory = File.dirname(Buildr.application.buildfile.to_s)
      if BuildrPlus::FeatureManager.activated?(:jenkins)
        existing = File.exist?("#{base_directory}/.jenkins") ? Dir["#{base_directory}/.jenkins/*.groovy"] : []
        BuildrPlus::Jenkins.jenkins_build_scripts.each_pair do |filename, content|
          full_filename = "#{base_directory}/#{filename}"
          existing.delete(full_filename)
          if content.nil?
            if File.exist?(full_filename)
              raise "The jenkins configuration file #{full_filename} exists when not expected. Please run \"buildr jenkins:fix\" and commit changes."
            end
          else
            if !File.exist?(full_filename) || IO.read(full_filename) != content
              raise "The jenkins configuration file #{full_filename} does not exist or is not up to date. Please run \"buildr jenkins:fix\" and commit changes."
            end
          end
        end
        unless existing.empty?
          raise "The following jenkins configuration file(s) exist but are not expected. Please run \"buildr jenkins:fix\" and commit changes.\n#{existing.collect { |e| "\t* #{e}" }.join("\n")}"
        end
      else
        if File.exist?("#{base_directory}/Jenkinsfile")
          raise 'The Jenkinsfile configuration file exists but the project does not have the jenkins facet enabled.'
        end
        if File.exist?("#{base_directory}/.jenkins")
          raise 'The .jenkins directory exists but the project does not have the jenkins facet enabled.'
        end
      end
    end

    task 'jenkins:fix' do
      if BuildrPlus::FeatureManager.activated?(:jenkins)
        base_directory = File.dirname(Buildr.application.buildfile.to_s)
        existing = File.exist?("#{base_directory}/.jenkins") ? Dir["#{base_directory}/.jenkins/*.groovy"] : []
        BuildrPlus::Jenkins.jenkins_build_scripts.each_pair do |filename, content|
          full_filename = "#{base_directory}/#{filename}"
          existing.delete(full_filename)
          if content.nil?
            FileUtils.rm_f full_filename
          else
            FileUtils.mkdir_p File.dirname(full_filename)
            File.open(full_filename, 'wb') do |file|
              file.write content
            end
          end
        end
        existing.each do |f|
          FileUtils.rm_f f
        end
      end
    end
  end
end

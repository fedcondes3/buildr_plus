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

module BuildrPlus
  module RepositoriesExtension
    module ProjectExtension
      include Extension
      BuildrPlus::ExtensionRegistry.register(self)

      first_time do
        Buildr.repositories.remote.unshift('https://stocksoftware.artifactoryonline.com/stocksoftware/public')
        Buildr.repositories.remote.unshift('http://repo.fire.dse.vic.gov.au/content/groups/fisg')
      end
    end
  end
end
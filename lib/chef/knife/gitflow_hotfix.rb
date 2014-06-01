#
## Author:: 
##  * Hector Rivas (<hector.rivas@springer.com>)
##  * Springer Platform Engineering (<platform-engineering@springer.com>)
##
## Based on original code from 
##  * knife-flow https://github.com/mdsol/knife-flow
##  * knife-spork https://github.com/jonlives/knife-spork
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
#
require 'chef/knife'
 
module KnifeGitFlow

  #
  # Command definition: gitflow hotfix start
  # 
  class GitflowHotfixStart < Chef::Knife
    deps do
      require 'chef/cookbook_loader'
      require 'chef/knife/core/object_loader'
    end

    banner "knife gitflow hotfix start"

    def run
      self.class.send(:include, KnifeGitFlow::Runner)
      check_git_clean!

      # TODO: Option to specify alternate subdirectory
      @cookbook_path = get_git_root
      @cookbook = load_cookbook

      new_version = bump_version(@cookbook.version, bump_type)

      gitflow_start_hotfix(new_version)
    end
  end

  #
  # Command definition: gitflow hotfix finish
  # 
  class GitflowHotfixFinish < Chef::Knife
    deps do
      require 'chef/cookbook_loader'
      require 'chef/knife/core/object_loader'
    end

    banner "knife gitflow hotfix finish"
    def run
      self.class.send(:include, KnifeGitFlow::Runner)

      check_git_clean!

      # TODO: Option to specify alternate subdirectory
      @cookbook_path = get_git_root
      @cookbook = load_cookbook

      hotfix_version = get_gitflow_hotfix_version

      update_metadata_version(hotfix_version)
      commit_bump_version!(hotfix_version)
      gitflow_finish_hotfix!(hotfix_version)
    end
  end 

  #
  # Command definition: gitflow release start
  # 
  class GitflowReleaseStart < Chef::Knife
    deps do
      require 'chef/cookbook_loader'
      require 'chef/knife/core/object_loader'
    end

    banner "knife gitflow release start [major|minor|patch|manual [version]]"

    def run
      self.class.send(:include, KnifeGitFlow::Runner)
      check_git_clean!

      # TODO: Option to specify alternate subdirectory
      @cookbook_path = get_git_root
      @cookbook = load_cookbook

      new_version = bump_version(@cookbook.version, bump_type)

      gitflow_start_release(new_version)
    end
  end

  #
  # Command definition: gitflow release finish
  # 
  class GitflowReleaseFinish < Chef::Knife
    deps do
      require 'chef/cookbook_loader'
      require 'chef/knife/core/object_loader'
    end

    banner "knife gitflow release finish"
    def run
      self.class.send(:include, KnifeGitFlow::Runner)

      check_git_clean!

      # TODO: Option to specify alternate subdirectory
      @cookbook_path = get_git_root
      @cookbook = load_cookbook

      release_version = get_gitflow_release_version

      update_metadata_version(release_version)
      commit_bump_version!(release_version)
      gitflow_finish_release!(release_version)
    end
  end 

  # 
  # Module Runner, including all helper functions
  # 
  TYPE_INDEX = { :major => 0, :minor => 1, :patch => 2, :manual => 3 }.freeze

  module Runner
    def get_git_root
      git_root=`git rev-parse --show-toplevel`
      raise "Error getting git root directory. Git installed or not a git repo? #{git_root}" if $?.exitstatus != 0
      git_root.strip
    end

    def load_cookbook
      loader = Chef::Cookbook::CookbookVersionLoader.new(@cookbook_path)
      loader.load_cookbooks
      loader.cookbook_version
    end

    def get_gitflow_hotfix_version
      output = `git flow hotfix list | awk '/^\* / {print $2}'`
      raise "Error getting hotfix version. Git are you in the hotfix branch? #{output}" if $?.exitstatus != 0
      version = output.strip
      validate_version!(version)
      version
    end

    def get_gitflow_release_version
      output = `git flow release list | awk '/^\* / {print $2}'`
      raise "Error getting release version. Git are you in the release branch? #{output}" if $?.exitstatus != 0
      version = output.strip
      validate_version!(version)
      version
    end

    def git_clean?
      `git diff --quiet HEAD`
      $?.exitstatus == 0
    end

    def check_git_clean!
      if not git_clean?
        ui.error "Git repository has uncommited changes. Commit or stash first."
        system("git status -s")
        exit 1
      end
    end

    def commit_bump_version!(new_version)
      system("git commit -m 'Bump version #{new_version}' metadata.rb")
      if $?.exitstatus != 0
        ui.error "Error commiting bump version."
        exit $?.exitstatus
      end
    end

    def gitflow_start_hotfix(new_version)
      output = `git flow hotfix start #{new_version}`
      if $?.exitstatus != 0
        ui.error "Failed starting git flow hotfix."
        exit $?.exitstatus
      end
      ui.info %Q{
Summary of actions:
- A new branch 'hotfix/#{new_version}' was created, based on 'master'
- You are now on branch 'hotfix/#{new_version}'

Follow-up actions:
- Start committing your hot fixes
- When done, run:

     knife gitflow hotfix finish
      }
    end

    def gitflow_finish_hotfix!(new_version)
      system("GIT_MERGE_AUTOEDIT=no git flow hotfix finish -m #{new_version} #{new_version}")
      if $?.exitstatus != 0
        ui.error "Failed finish git flow hotfix #{new_version}."
        exit $?.exitstatus
      end
    end

    def gitflow_start_release(new_version)
      output = `git flow release start #{new_version}`
      if $?.exitstatus != 0
        ui.error "Failed starting git flow release."
        exit $?.exitstatus
      end
      ui.info %Q{
Summary of actions:
- A new branch 'release/#{new_version}' was created, based on 'develop'
- You are now on branch 'release/#{new_version}'

Follow-up actions:
- Start committing last-minute fixes in preparing your release
- When done, run:

     knife gitflow release finish
      }
    end

    def gitflow_finish_release!(new_version)
      system("GIT_MERGE_AUTOEDIT=no git flow release finish -m #{new_version} #{new_version}")
      if $?.exitstatus != 0
        ui.error "Failed finish git flow release #{new_version}."
        exit $?.exitstatus
      end
    end

    def bump_version(old_version, bump_type)
      if bump_type == 3
        # manual bump
        version_array = manual_bump_version.split('.')
      else
        # major, minor, or patch bump
        version_array = old_version.split('.').collect{ |i| i.to_i }
        version_array[bump_type] += 1
        ((bump_type+1)..2).each{ |i| version_array[i] = 0 } # reset all lower version numbers to 0
      end

      version_array.join('.')
    end

    def bump_type
      TYPE_INDEX[(name_args[0] || 'patch').to_sym]
    end

    def manual_bump_version
      version = name_args.last
      validate_version!(version)
      version
    end

    def valid_version?(version)
      version_keys = version.split('.')
      return false unless version_keys.size == 3 && version_keys.any?{ |k| begin Float(k); rescue false; else true; end }
      true
    end

    def validate_version!(version)
      if version && !valid_version?(version)
        ui.error("#{version} is not a valid version!")
        exit(1)
      end
    end

    def update_metadata_version(new_version)
      metadata_file = "#{@cookbook.root_dir}/metadata.rb"
      new_contents = File.read(metadata_file).gsub(/(version\s+['"])[0-9\.]+(['"])/, "\\1#{new_version}\\2")
      File.open(metadata_file, 'w'){ |f| f.write(new_contents) }

      ui.info "Successfully bumped #{@cookbook.name} to v#{new_version}!"
    end
  
  end


end

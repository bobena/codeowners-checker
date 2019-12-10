# frozen_string_literal: true

require 'git'
require 'logger'

require_relative 'checker/code_owners'
require_relative 'checker/file_as_array'
require_relative 'checker/group'
require_relative 'checker/owners_list'

module Codeowners
  # Check if code owners are consistent between a git repository and the CODEOWNERS file.
  # It compares what's being changed in the PR and check if the current files and folders
  # are also being declared in the CODEOWNERS file.
  # By default (:validate_owners property) it also reads OWNERS with list of all
  # possible/valid owners and validates every owner in CODEOWNERS is defined in OWNERS
  class Checker
    attr_reader :owners_list

    # Get repo metadata and compare with the owners
    def initialize(repo, from, to)
      @git = Git.open(repo, log: Logger.new(IO::NULL))
      @repo_dir = repo
      @from = from || 'HEAD'
      @to = to
      @owners_list = OwnersList.new(@repo_dir)
    end

    def changes_to_analyze
      @git.diff(@from, @to).name_status
    end

    def added_files
      changes_to_analyze.select { |_k, v| v == 'A' }.keys
    end

    def fix!
      catch(:user_quit) { results }
    end

    def changes_for_patterns(patterns)
      @git.diff(@from, @to).path(patterns).name_status.keys
    end

    def patterns_by_owner
      @patterns_by_owner ||=
        codeowners.each_with_object(hash_of_arrays) do |line, patterns_by_owner|
          next unless line.pattern?

          line.owners.each { |owner| patterns_by_owner[owner] << line.pattern.gsub(%r{^/}, '') }
        end
    end

    def hash_of_arrays
      Hash.new { |h, k| h[k] = [] }
    end

    def changes_with_ownership(owner = '')
      patterns_by_owner.each_with_object({}) do |(own, patterns), changes_with_owners|
        next if (owner != '') && (own != owner)

        changes_with_owners[own] = changes_for_patterns(patterns)
      end
    end

    def useless_pattern
      @useless_pattern ||= codeowners.select do |line|
        line.pattern? && !pattern_has_files(line.pattern)
      end
    end

    def missing_reference
      @missing_reference ||= added_files.reject(&method(:defined_owner?))
    end

    def pattern_has_files(pattern)
      @git.ls_files(pattern.gsub(%r{^/}, '')).any?
    end

    def defined_owner?(file)
      codeowners.find do |line|
        next unless line.pattern?

        return true if line.match_file?(file)
      end

      @when_new_file&.call(file) if @when_new_file
      false
    end

    def codeowners
      @codeowners ||= CodeOwners.new(
        FileAsArray.new(CodeOwners.filename(@repo_dir))
      )
    end

    def main_group
      codeowners.main_group
    end

    def consistent?
      results.none?
    end

    def commit_changes!
      @git.add(@codeowners.filename)
      @git.add(@owners_list.filename)
      @git.commit('Fix pattern :robot:')
    end

    def unrecognized_line
      @unrecognized_line ||= codeowners.select { |line| line.is_a?(Codeowners::Checker::Group::UnrecognizedLine) }
    end

    private

    def invalid_owners
      @invalid_owners ||= @owners_list.invalid_owner(@codeowners)
    end

    def results
      @results ||= Enumerator.new do |yielder|
        missing_reference.each { |ref| yielder << [:missing_ref, ref] }
        useless_pattern.each { |pattern| yielder << [:useless_pattern, pattern] }
        invalid_owners.each { |(owner, missing)| yielder << [:invalid_owner, owner, missing] }
        unrecognized_line.each { |line| yielder << [:unrecognized_line, line] }
      end
    end
  end
end

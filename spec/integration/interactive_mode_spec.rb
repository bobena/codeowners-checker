# frozen_string_literal: true

require 'codeowners/checker'

RSpec.describe 'Interactive mode' do
  def codeowners_file_body
    File.open(File.join(IntegrationTestRunner::PROJECT_PATH, '.github', 'CODEOWNERS')).read
  end

  def owners_file_body
    File.open(File.join(IntegrationTestRunner::PROJECT_PATH, '.github', 'OWNERS')).read
  end

  subject(:runner) do
    IntegrationTestRunner
      .new(codeowners: codeowners, owners: owners, file_tree: file_tree, answers: answers)
      .run
  end

  let(:codeowners) { [] }
  let(:owners) { [] }
  let(:file_tree) { {} }
  let(:answers) { [] }

  context 'when no issues' do
    let(:codeowners) { ['lib/new_file.rb @mpospelov'] }
    let(:owners) { ['@mpospelov'] }
    let(:file_tree) { { 'lib/new_file.rb' => 'bar' } }

    it { is_expected.to report_with('✅ File is consistent') }
  end

  context 'when user_quit is pressed' do
    let(:file_tree) { { 'lib/new_file.rb' => 'bar' } }
    let(:answers) { ['q'] }

    it 'asks about missing owner file' do
      expect(runner).to ask(<<~QUESTION).limited_to(%w[y i q])
        File added: "lib/new_file.rb". Add owner to the CODEOWNERS file?
        (y) yes
        (i) ignore
        (q) quit and save
      QUESTION
    end
  end

  context 'when missing_ref issue' do
    let(:file_tree) { { 'lib/new_file.rb' => 'bar' } }

    it 'asks about missing owner file' do
      expect(runner).to ask(<<~QUESTION).limited_to(%w[y i q])
        File added: "lib/new_file.rb". Add owner to the CODEOWNERS file?
        (y) yes
        (i) ignore
        (q) quit and save
      QUESTION
    end
  end

  context 'when useless_pattern issue' do
    let(:codeowners) { ['lib/new_file.rb @mpospelov', 'liba/* @mpospelov'] }
    let(:owners) { ['@mpospelov'] }
    let(:file_tree) { { 'lib/new_file.rb' => 'bar' } }

    it 'ask to edit useless paterns from codeowners' do
      allow(Codeowners::Cli::SuggestFileFromPattern).to receive(:installed_fzf?).and_return(false)
      expect(runner).to ask(<<~QUESTION).limited_to(%w[i e d q])
        (e) edit the pattern
        (d) delete the pattern
        (i) ignore
        (q) quit and save
      QUESTION
    end

    context 'with fzf installed' do
      def expect_to_run_fzf_suggestion(with_pattern:)
        search_mock = instance_double('Codeowners::Cli::FilesFromFZFSearch')
        expect(Codeowners::Cli::FilesFromFZFSearch).to receive(:new).with(with_pattern) { search_mock }
        expect(search_mock).to receive(:pick_suggestions) { yield }
      end

      before { allow(Codeowners::Cli::SuggestFileFromPattern).to receive(:installed_fzf?).and_return(true) }

      it 'ask to edit useless paterns with suggestion from codeowners' do
        expect_to_run_fzf_suggestion(with_pattern: 'liba/*') { 'lib/' }
        expect(runner).to ask(<<~QUESTION).limited_to(%w[y i e d q])
          Replace with: "lib/"?
          (y) yes
          (i) ignore
          (e) edit the pattern
          (d) delete the pattern
          (q) quit and save
        QUESTION
      end
    end
  end

  context 'when invalid_owner issue' do
    let(:codeowners) { ['lib/new_file.rb @mpospelov @foobar'] }
    let(:owners) { ['@mpospelov'] }
    let(:file_tree) { { 'lib/new_file.rb' => 'bar' } }
    let(:answers) { ['r', '@mpospelov', 'a'] }

    it 'asks to add new owner to owners' do
      question = <<~QUESTION
        Unknown owner: @foobar for pattern: lib/new_file.rb. Choose an option:
        (a) add a new owner
        (r) rename owner
        (i) ignore owner in this session
        (q) quit and save
      QUESTION
      expect(runner)
        .to ask(question)
        .limited_to(%w[a r i q])
        .and ask('New owner: ')
        .and ask('Commit changes?')
      expect(codeowners_file_body).to eq("lib/new_file.rb @mpospelov\n")
      expect(owners_file_body.scan('@mpospelov')).to contain_exactly('@mpospelov')
    end

    context 'when the owner`s name was misspelled' do
      let(:owners) { %w[@mpospelov @foobaz] }
      let(:answers) { ['y'] }

      it 'asks to add new owner to owners' do
        question = <<~QUESTION
          Unknown owner: @foobar for pattern: lib/new_file.rb. Did you mean @foobaz?
          (y) correct to @foobaz
          (a) add a new owner
          (r) rename owner
          (i) ignore owner in this session
          (q) quit and save
        QUESTION
        expect(runner)
          .to ask(question)
          .limited_to(%w[y a r i q])
        expect(codeowners_file_body).to eq("lib/new_file.rb @mpospelov @foobaz\n")
        expect(owners_file_body.scan('@foobaz')).to contain_exactly('@foobaz')
      end
    end
  end

  context 'when unrecognized_line issue' do
    let(:codeowners) { ['lib/new_file.rb @mpospelov', '@mpospelov'] }
    let(:owners) { ['@mpospelov'] }
    let(:file_tree) { { 'lib/new_file.rb' => 'bar' } }

    it 'asks to edit or delete unrecognized lines' do
      expect(runner).to ask(<<~QUESTION).limited_to(%w[y i d])
        "@mpospelov" is in unrecognized format. Would you like to edit?
        (y) yes
        (i) ignore
        (d) delete the line
      QUESTION
    end
  end
end

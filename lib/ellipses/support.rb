# frozen_string_literal: true

require "digest"
require "set"
require "pathname"
require "open3"

# Generic helpers

module Ellipses
  module Support
    module_function

    def digest(*args)
      ::Digest::SHA256.hexdigest args.map(&:to_s).join
    end

    def to_range(index_or_range)
      case index_or_range
      when Range then index_or_range
      when Integer then Range.new(index_or_range, index_or_range)
      else raise ArgumentError, "Integer or a Range expected where found: #{index_or_range.class}"
      end
    end

    def intersperse_arrays(arrays, intersperse)
      interspersed = []
      arrays.each { |array| interspersed.append(array, intersperse) }
      interspersed.pop
      interspersed
    end

    def prefix_non_blank(string, prefix, excludes: nil)
      stripped = string.strip

      return string if prefix.empty? || stripped.empty?
      return string if excludes && [*excludes].include?(stripped)

      "#{prefix}#{string}"
    end

    class PathSanitizer
      def self.sanitize(*args, **kwargs)
        new(*args, **kwargs).sanitize
      end

      class Error < StandardError
        def initialize(path)
          super("#{kind}: #{path}")
        end

        def self.kind(message)
          Class.new self do
            define_method(:kind) { message }
          end
        end
      end

      MissingBase   = Error.kind "Directory not found"
      WrongBase     = Error.kind "Not a directory"
      MissingPath   = Error.kind "File or directory not found"
      NotFile       = Error.kind "Not a file"
      NotDir        = Error.kind "Not a directory"
      NotExecutable = Error.kind "Not an executable"

      attr_reader :path, :base, :fullpath, :relpath

      def initialize(path:, base: nil)
        @path     = ::File.join(*path)
        @base     = ::File.join(*base) if base

        @fullpath = ::File.expand_path(@path, @base)
      end

      def sanitize
        if base
          raise MissingBase, base unless ::File.exist?(base)
          raise WrongBase,   base unless ::File.directory?(base)
        end

        raise MissingPath, fullpath unless ::File.exist?(fullpath)

        call

        fullpath
      end

      class Dir < PathSanitizer
        def call
          raise NotDir, fullpath unless ::File.directory?(fullpath)
        end
      end

      private_constant :Dir

      class File < PathSanitizer
        def call
          raise NotFile, fullpath unless ::File.file?(fullpath)
        end
      end

      private_constant :File

      class Executable < PathSanitizer
        def call
          raise NotExecutable, fullpath unless ::File.file?(fullpath) || ::File.executable?(fullpath)
        end
      end

      private_constant :Executable
    end

    private_constant :PathSanitizer

    %i[file dir executable].each do |meth|
      klass = PathSanitizer.const_get meth.capitalize

      define_method(meth) do |path, base: nil|
        klass.sanitize(path: path, base: base)
      rescue PathSanitizer::Error
        nil
      end

      define_method("#{meth}!") do |path, error: nil, base: nil|
        klass.sanitize(path: path, base: base)
      rescue PathSanitizer::Error => e
        error ? raise(error, e.message) : raise
      end
    end

    def expand_path(path, rootdir = nil)
      Pathname.new(::File.join(rootdir || ".", path)).cleanpath.to_s
    end

    def deflate_path(path, rootdir = nil)
      base = Pathname.new(rootdir || ".").expand_path
      Pathname.new(path).cleanpath.expand_path.relative_path_from(base).to_s
    end

    def update_file(file, lines)
      old = ::File.exist?(file) ? ::File.read(file) : nil
      new = "#{[*lines].join.chomp}\n"

      if old && old == new
        false
      else
        ::File.write(file, new)
        true
      end.tap { |status| yield(status) if block_given? }
    end

    module Color
      # rubocop:disable Layout/SpaceInsideArrayPercentLiteral
      %w[
        black   0
        blue    39
        cyan    14
        green   35
        magenta 200
        orange  214
        red     197
        violet  140
        white   15
        yellow  11
      ].each_slice(2) do |color, code|
        singleton_class.send(:define_method, color) { |string| "\e[38;5;#{code}m#{string}\e[0m" }
      end

      %w[
        bold       1
        dim        2
        underlined 4
        blink      5
        reverse    7
        hidden     8
      ].each_slice(2) do |attr, code|
        singleton_class.send(:define_method, attr) { |string| "\e[#{code}m#{string}\e[0m" }
      end
      # rubocop:enable Layout/SpaceInsideArrayPercentLiteral
    end

    def notice(string)
      "#{Color.bold Color.green "✓"}  #{string}"
    end

    def info(string)
      "#{Color.bold Color.green "✓"}  #{Color.dim string}"
    end

    def error(string)
      "#{Color.bold Color.red "✗"}  #{string}"
    end

    def warning(string)
      "#{Color.bold Color.yellow "!"}  #{string}"
    end

    module Shell
      Result = Struct.new :args, :out, :err, :exit_code do
        def outline
          out.first
        end

        def ok?
          exit_code&.zero?
        end

        def notok?
          !ok?
        end

        def cmd
          args.join " "
        end
      end

      # Adapted to popen3 from github.com/mina-deploy/mina
      class Runner
        def initialize
          @coathooks = 0
        end

        def run(*args)
          return dummy_result if args.empty?

          out, err, status =
            Open3.popen3(*args) do |_, stdout, stderr, wait_thread|
              block(stdout, stderr, wait_thread)
            end
          Result.new args, out, err, status.exitstatus
        end

        private

        def block(stdout, stderr, wait_thread)
          # Handle `^C`
          trap("INT") { handle_sigint(wait_thread.pid) }

          out = stdout.readlines.map(&:chomp)
          err = stderr.readlines.map(&:chomp)

          [out, err, wait_thread.value]
        end

        def handle_sigint(pid) # rubocop:disable Metrics/MethodLength
          message, signal = if @coathooks > 1
                              ["SIGINT received again. Force quitting...", "KILL"]
                            else
                              ["SIGINT received.", "TERM"]
                            end

          warn
          warn message
          ::Process.kill signal, pid
          @coathooks += 1
        rescue Errno::ESRCH
          warn "No process to kill."
        end
      end

      module_function

      def run(*args)
        Runner.new.run(*args)
      end

      def fake(*args)
        dummy_result(args)
      end

      def dummy_result(args = [])
        Result.new args, [], [], 0
      end
    end

    module Struct
      refine ::Struct.singleton_class do
        def from_hash_without_bogus_keys!(hash, error:)
          hash  = hash.transform_keys(&:to_sym)
          clean = hash.slice(*members)
          bogus = hash.keys.reject { |key| members.include?(key) }

          raise error, "Bogus keys found: #{bogus}" unless bogus.empty?

          new clean
        end
      end
    end
  end
end

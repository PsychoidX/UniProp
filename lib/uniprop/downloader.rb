require 'fileutils'
require 'open-uri'
require 'pathname'
begin
  require 'net/https'
rescue LoadError
  https = 'http'
else
  https = 'https'

  # open-uri of ruby 2.2.0 accepts an array of PEMs as ssl_ca_cert, but old
  # versions do not.  so, patching OpenSSL::X509::Store#add_file instead.
  class OpenSSL::X509::Store
    alias orig_add_file add_file
    def add_file(pems)
      Array(pems).each do |pem|
        if File.directory?(pem)
          add_path pem
        else
          orig_add_file pem
        end
      end
    end
  end
  # since open-uri internally checks ssl_ca_cert using File.directory?,
  # allow to accept an array.
  class <<File
    alias orig_directory? directory?
    def File.directory? files
      files.is_a?(Array) ? false : orig_directory?(files)
    end
  end
end

class Downloader
  def self.https=(https)
    @@https = https
  end

  def self.https?
    @@https == 'https'
  end

  def self.https
    @@https
  end

  def self.mode_for(data)
    /\A#!/ =~ data ? 0755 : 0644
  end

  def self.http_options(file, since)
    options = {}
    if since
      case since
      when true
        since = (File.mtime(file).httpdate rescue nil)
      when Time
        since = since.httpdate
      end
      if since
        options['If-Modified-Since'] = since
      end
    end
    options['Accept-Encoding'] = 'identity' # to disable Net::HTTP::GenericRequest#decode_content
    options
  end

  def self.httpdate(date)
    Time.httpdate(date)
  rescue ArgumentError => e
    # Some hosts (e.g., zlib.net) return similar to RFC 850 but 4
    # digit year, sometimes.
    /\A\s*
     (?:Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day,\x20
     (\d\d)-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d{4})\x20
     (\d\d):(\d\d):(\d\d)\x20
     GMT
     \s*\z/ix =~ date or raise
    warn e.message
    Time.utc($3, $2, $1, $4, $5, $6)
  end

  def self.download(url, name, dir = nil, since = true, options = {})
    options = options.dup
    url = URI(url)
    dryrun = options.delete(:dryrun)
    options.delete(:unicode_beta) # just to be on the safe side for gems and gcc

    if name
      file = Pathname.new(under(dir, name))
    else
      name = File.basename(url.path)
    end
    cache_save = options.delete(:cache_save) {
      ENV["CACHE_SAVE"] != "no"
    }
    cache = cache_file(url, name, options.delete(:cache_dir))
    file ||= cache
    if since.nil? and file.exist?
      if $VERBOSE
        $stdout.puts "#{file} already exists"
        $stdout.flush
      end
      if cache_save
        save_cache(cache, file, name)
      end
      return file.to_path
    end
    if dryrun
      puts "Download #{url} into #{file}"
      return
    end
    if link_cache(cache, file, name, $VERBOSE)
      return file.to_path
    end
    if !https? and URI::HTTPS === url
      warn "*** using http instead of https ***"
      url.scheme = 'http'
      url = URI(url.to_s)
    end
    if $VERBOSE
      $stdout.print "downloading #{name} ... "
      $stdout.flush
    end
    mtime = nil
    options = options.merge(http_options(file, since.nil? ? true : since))
    begin
      data = with_retry(10) do
        data = url.read(options)
        if mtime = data.meta["last-modified"]
          mtime = Time.httpdate(mtime)
        end
        data
      end
    rescue OpenURI::HTTPError => http_error
      if http_error.message =~ /^304 / # 304 Not Modified
        if $VERBOSE
          $stdout.puts "not modified"
          $stdout.flush
        end
        return file.to_path
      end
      raise
    rescue Timeout::Error
      if since.nil? and file.exist?
        puts "Request for #{url} timed out, using old version."
        return file.to_path
      end
      raise
    rescue SocketError
      if since.nil? and file.exist?
        puts "No network connection, unable to download #{url}, using old version."
        return file.to_path
      end
      raise
    end
    dest = (cache_save && cache && !cache.exist? ? cache : file)
    dest.parent.mkpath
    dest.open("wb", 0600) do |f|
      data.scrub!('?') # invalid byte sequence in UTF-8 対策
      f.write(data)
      f.chmod(mode_for(data))
    end
    if mtime
      dest.utime(mtime, mtime)
    end
    if $VERBOSE
      $stdout.puts "done"
      $stdout.flush
    end
    if dest.eql?(cache)
      link_cache(cache, file, name)
    elsif cache_save
      save_cache(cache, file, name)
    end
    return file.to_path
  rescue => e
    raise "failed to download #{name}\n#{e.class}: #{e.message}: #{url}"
  end

  def self.under(dir, name)
    dir ? File.join(dir, File.basename(name)) : name
  end

  def self.cache_file(url, name, cache_dir = nil)
    case cache_dir
    when false
      return nil
    when nil
      cache_dir = ENV['CACHE_DIR']
      if !cache_dir or cache_dir.empty?
        cache_dir = ".downloaded-cache"
      end
    end
    Pathname.new(cache_dir) + (name || File.basename(URI(url).path))
  end

  def self.link_cache(cache, file, name, verbose = false)
    return false unless cache and cache.exist?
    return true if cache.eql?(file)
    if /cygwin/ !~ RUBY_PLATFORM or /winsymlink:nativestrict/ =~ ENV['CYGWIN']
      begin
        file.make_symlink(cache.relative_path_from(file.parent))
      rescue SystemCallError
      else
        if verbose
          $stdout.puts "made symlink #{name} to #{cache}"
          $stdout.flush
        end
        return true
      end
    end
    begin
      file.make_link(cache)
    rescue SystemCallError
    else
      if verbose
        $stdout.puts "made link #{name} to #{cache}"
        $stdout.flush
      end
      return true
    end
  end

  def self.save_cache(cache, file, name)
    return unless cache or cache.eql?(file)
    begin
      st = cache.stat
    rescue
      begin
        file.rename(cache)
      rescue
        return
      end
    else
      return unless st.mtime > file.lstat.mtime
      file.unlink
    end
    link_cache(cache, file, name)
  end

  def self.with_retry(max_times, &block)
    times = 0
    begin
      block.call
    rescue Errno::ETIMEDOUT, SocketError, OpenURI::HTTPError, Net::ReadTimeout, Net::OpenTimeout, ArgumentError => e
      raise if e.is_a?(OpenURI::HTTPError) && e.message !~ /^50[023] / # retry only 500, 502, 503 for http error
      times += 1
      if times <= max_times
        $stderr.puts "retrying #{e.class} (#{e.message}) after #{times ** 2} seconds..."
        sleep(times ** 2)
        retry
      else
        raise
      end
    end
  end
  private_class_method :with_retry
end

Downloader.https = https.freeze
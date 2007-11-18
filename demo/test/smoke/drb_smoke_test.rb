# Simple smoke test for the DRb server
# usage: 
#
# # start the DRb server
# script/ferret_server -e test start
#
# # run the script
# AAF_REMOTE=true script/runner -e test test/smoke/drb_smoke_test.rb

module DrbSmokeTest

  RECORDS_PER_PROCESS = 100000
  NUM_PROCESSES       = 10 # should be an even number
  NUM_RECORDS_PER_LOGENTRY = 10
  NUM_DOCS = 50
  NUM_TERMS = 600

  TIME_FACTOR = 1000.to_f / NUM_RECORDS_PER_LOGENTRY

  class Words
    DICTIONARY = '/usr/share/dict/words'
    def initialize
      @words = []
      File.open(DICTIONARY) do |file|
        file.each_line do |word|
          @words << word.strip unless word =~ /'/
        end
      end
    end

    def to_s
      "#{@words.size} words"
    end

    def random_word
      @words[rand(@words.size)]
    end
  end

  puts "compiling sample documents..."
  WORDS = Words.new
  puts WORDS
  DOCUMENTS = []

  NUM_DOCS.times do
    doc = ''
    NUM_TERMS.times { doc << WORDS.random_word << ' ' }
    DOCUMENTS << doc
  end

  def self.random_document
    DOCUMENTS[rand(DOCUMENTS.size)]
  end

  puts "built #{NUM_DOCS} documents with an avg. size of #{DOCUMENTS.join.size / NUM_DOCS} Bytes."

  class Monitor
    class << self
      def count_connections
        res = Content.connection.execute("show status where variable_name = 'Threads_connected'")
        if res
          res.fetch_row.last
        else
          "error getting connection count"
        end
      end
      def running?
        Stats.count_by_sql("select count(*) from stats where kind='finished'") < (NUM_PROCESSES/2)
      end
    end
  end

  class TestBase
    def initialize(id)
      @id = id
      @time = 0
    end

    def get_time
      returning(Time.now - @t1) do
        @t1 = Time.now
      end
    end

    def benchmark
      t = Time.now
      yield
      Time.now - t
    end

  end

  class Writer < TestBase
    def run
      RECORDS_PER_PROCESS.times do |i|
        @time += benchmark do
          Content.create! :title => "record #{@id} / #{i}", :description => DrbSmokeTest::random_document
        end
        #sleep 0.1
        if i % NUM_RECORDS_PER_LOGENTRY == 0
          # write stats
          puts "#{@id}: #{i} records indexed, last #{NUM_RECORDS_PER_LOGENTRY} in #{@time}"
          Stats.create! :process_id => @id, :kind => 'write', :info => i, 
                        :processing_time => @time * TIME_FACTOR,        # average processing time per record in this batch
                        :open_connections => Monitor::count_connections
          @time = 0
        end
      end
      Stats.create! :process_id => @id, :kind => 'finished'
      puts "#{@i} finished"
    end
  end

  class Searcher < TestBase
    def run
      while Monitor::running?
        # search with concurrent writes
          do_search
      end
      t = Time.now
      while (Time.now - t) < 5.minutes
        # the writers have finished, now hammer the server with searches for another 5 minutes
        do_search
      end
      puts "#{@i} finished"
    end

    # run a search and log it's results.
    # Search is done with a query consisting of the term 'findme' 
    # (which is guaranteed to yield 20 results) and a random term from 
    # the word list, ORed together
    def do_search
      hits = 0
      time = benchmark do
        NUM_RECORDS_PER_LOGENTRY.times do
          result = Content.find_id_by_contents "findme OR #{WORDS.random_word}"
          hits += result.first
        end
      end
      Stats.create! :process_id => @id, :kind => 'search', :info => "avg total_hits: #{hits/NUM_RECORDS_PER_LOGENTRY.to_f}", 
                    :processing_time => time * TIME_FACTOR,
                    :open_connections => Monitor::count_connections
    end

  end

  def self.run
    @start = Time.now

    NUM_PROCESSES.times do |i|
      unless fork
        @id = i
        break
      end
    end

    if @id
      @id.even? ? Writer.new(@id).run : Searcher.new(@id).run
    else

      # create some records to search for
      20.times do |i|
        Content.create! :title => "to find #{i}", :description => ("findme #{i} " << random_document)
      end

      while Monitor::running?
        puts "open connections: #{Monitor::count_connections}; time elapsed: #{Time.now - @start} seconds"
        sleep 10 
      end
    end
  end
end

DrbSmokeTest::run
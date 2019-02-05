module ActsAsFerret

  # mixed into the FerretResult and AR classes calling acts_as_ferret
  module ResultAttributes
    # holds the score this record had when it was found via
    # acts_as_ferret
    attr_accessor :ferret_score

    attr_accessor :ferret_rank
  end

  class FerretResult < ActsAsFerret::BlankSlate
    include ResultAttributes
    attr_accessor :id

    def initialize(model, id, score, field_scores, rank, data = {})
      @model = model.constantize
      @id = id
      @ferret_score = score
      @ferret_field_scores = field_scores
      @ferret_rank  = rank
      @data = data
      @use_record = false
    end

    def inspect
      "#<FerretResult wrapper for #{@model} with id #{@id}>"
    end

    def method_missing(method, *args, &block)
      if method == :highlight
        @model.send method, id, *args
      elsif (@ar_record && @use_record) || !@data.has_key?(method)
        to_record.send method, *args, &block
      else
        @data[method]
      end
    end

    def respond_to?(name)
      [ :ferret_score, :ferret_rank, :highlight,
        :inspect, :method_missing, :respond_to?, :to_record, :to_param, :id
      ].include?(name) ||
        @data.has_key?(name.to_sym) || to_record.respond_to?(name)
    end

    def to_record
      unless @ar_record
        @ar_record = @model.find(id)
        @ar_record.ferret_rank  = ferret_rank
        @ar_record.ferret_score = ferret_score
        # don't try to fetch attributes from RDig based records
        @use_record = !@ar_record.class.included_modules.include?(::ActsAsFerret::RdigAdapter)
      end
      @ar_record
    end
    
    def to_param
      return @id
    end
    
  end
end

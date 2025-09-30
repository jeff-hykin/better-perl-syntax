require 'json'
require 'yaml'
require 'set'
require 'deep_clone' # gem install deep_clone
require 'pathname'

#
# this is to help make patterns lik "tokens.that(:areWords, !:areControlFlow)"
#
class TokenHelper
    attr_accessor :tokens
    def initialize(tokens, for_each_token:nil)
        @tokens = tokens
        if for_each_token != nil
            for each in @tokens
                for_each_token[each]
            end
        end
    end


    def tokensThat(*adjectives)
        matches = @tokens.select do |each_token|
            output = true
            for each_adjective in adjectives
                # make sure to fail on negated symbols
                if each_adjective.is_a? NegatedSymbol
                    if each_token[each_adjective.to_sym] == true
                        output = false
                        break
                    end
                elsif each_token[each_adjective] != true
                    output = false
                    break
                end
            end
            output
        end
        # sort from longest to shortest
        matches.sort do |token1, token2|
            token2[:representation].length - token1[:representation].length
        end
    end

    def representationsThat(*adjectives)
        matches = self.tokensThat(*adjectives)
        return matches.map do |each| each[:representation] end
    end

    def lookBehindToAvoidWordsThat(*adjectives)
        array_of_invalid_names = self.representationsThat(*adjectives)
        if array_of_invalid_names.size == 0
            return Pattern.new(//)
        end
        return Pattern.new(/\b/).lookBehindToAvoid(/#{array_of_invalid_names.map { |each| '\W'+each+'|^'+each } .join('|')}/)
    end

    def lookAheadToAvoidWordsThat(*adjectives)
        array_of_invalid_names = self.representationsThat(*adjectives)
        if array_of_invalid_names.size == 0
            return Pattern.new(//)
        end
        return Pattern.new(/\b/).lookAheadToAvoid(/#{array_of_invalid_names.map { |each| each+'\W|'+each+'\$' } .join('|')}/)
    end

    def that(*adjectives)
        representations = representationsThat(*adjectives)
        if representations.size == 0
            return Pattern.new(//)
        end
        regex_internals = representations.map do |each|
             Regexp.escape(each)
        end.join('|')
        return Pattern.new(/(?:#{regex_internals})/)
        # oneOf has problems (as of 2024-07)
        # return oneOf(representationsThat(*adjectives))
    end
end

#
# These monkey patch the builtin Symbol to allow for easy negation
#
# (not the greatest developer pattern, but makes it more readable in main.rb)
class NegatedSymbol
    def initialize(a_symbol)
        @symbol = a_symbol
    end
    def to_s
        return "not(#{@symbol.to_s})"
    end
    def to_sym
        return @symbol
    end
end

class Symbol
    def !@
        return NegatedSymbol.new(self)
    end
end
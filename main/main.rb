require 'json'
require 'yaml'
require 'fileutils'
require 'pathname'

require 'ruby_grammar_builder'
require_relative './tokens.rb'

# 
# 
# Perl grammar
# 
# 
grammar = Grammar.fromTmLanguage("./main/modified.tmLanguage.json")

# 
# Builtin Helpers (part of ruby grammar builder)
# 
    # @space
    # @spaces
    # @digit
    # @digits
    # @standard_character
    # @word
    # @word_boundary
    # @white_space_start_boundary
    # @white_space_end_boundary
    # @start_of_document
    # @end_of_document
    # @start_of_line
    # @end_of_line

#
# Custom Helpers
#
    part_of_a_variable = /[a-zA-Z_][a-zA-Z0-9_]*/
    @standard_character = /[a-zA-Z0-9_]/
    # this is really useful for keywords. eg: variableBounds[/new/] wont match "newThing" or "thingnew"
    variableBounds = ->(regex_pattern) do
        lookBehindToAvoid(@standard_character).then(regex_pattern).lookAheadToAvoid(@standard_character)
    end
    @variable = variable = variableBounds[part_of_a_variable].then(@tokens.lookBehindToAvoidWordsThat(:areKeywords))

# 
# shared patterns
# 
    def numeric_constant(allow_user_defined_literals: false, separator:"'")
        # both C and C++ treat any sequence of digits, letter, periods, and valid separators
        # as a single numeric constant even if such a sequence forms no valid
        # constant/literal
        # additionally +- are part of the sequence when immediately succeeding e,E,p, or P.
        # the outer range pattern does not attempt to actually process the numbers
        valid_single_character = /(?:[0-9a-zA-Z_\.]|#{separator})/
        valid_after_exponent = lookBehindFor(/[eEpP]/).then(/[+-]/)
        valid_character = Pattern.new(valid_single_character).or(valid_after_exponent)
        end_pattern = /$/
        
        number_separator_pattern = Pattern.new(
            should_partial_match: [ "1#{separator}1" ],
            should_not_partial_match: [ "1#{separator}#{separator}1", "1#{separator}#{separator}" ],
            match: lookBehindFor(/[0-9a-fA-F]/).then(/#{separator}/).lookAheadFor(/[0-9a-fA-F]/),
            tag_as:"punctuation.separator.constant.numeric",
            )

        hex_digits = hex_digits = Pattern.new(
            should_fully_match: [ "1", "123456", "DeAdBeeF", "49#{separator}30#{separator}94", "DeA#{separator}dBe#{separator}eF", "dea234f4930" ],
            should_not_fully_match: [ "#{separator}3902" , "de2300p1000", "0x000" ],
            should_not_partial_match: [ "p", "x", "." ],
            match: Pattern.new(/[0-9a-fA-F]/).zeroOrMoreOf(Pattern.new(/[0-9a-fA-F]/).or(number_separator_pattern)),
            tag_as: "constant.numeric.hexadecimal",
            includes: [ number_separator_pattern ],
            )
        decimal_digits = Pattern.new(
            should_fully_match: [ "1", "123456", "49#{separator}30#{separator}94" , "1#{separator}2" ],
            should_not_fully_match: [ "#{separator}3902" , "1.2", "0x000" ],
            match: Pattern.new(/[0-9]/).zeroOrMoreOf(Pattern.new(/[0-9]/).or(number_separator_pattern)),
            tag_as: "constant.numeric.decimal",
            includes: [ number_separator_pattern ],
            )
        # 0'004'000'000 is valid (i.e. a number separator directly after the prefix)
        octal_digits = Pattern.new(
            should_fully_match: [ "1", "123456", "47#{separator}30#{separator}74" , "1#{separator}2" ],
            should_not_fully_match: [ "#{separator}3902" , "1.2", "0x000" ],
            match: oneOrMoreOf(Pattern.new(/[0-7]/).or(number_separator_pattern)),
            tag_as: "constant.numeric.octal",
            includes: [ number_separator_pattern ],
            )
        binary_digits = Pattern.new(
            should_fully_match: [ "1", "100100", "10#{separator}00#{separator}11" , "1#{separator}0" ],
            should_not_fully_match: [ "#{separator}3902" , "1.2", "0x000" ],
            match: Pattern.new(/[01]/).zeroOrMoreOf(Pattern.new(/[01]/).or(number_separator_pattern)),
            tag_as: "constant.numeric.binary",
            includes: [ number_separator_pattern ],
            )

        hex_prefix = Pattern.new(
            should_fully_match: ["0x", "0X"],
            should_partial_match: ["0x1234"],
            should_not_partial_match: ["0b010x"],
            match: Pattern.new(/\G/).then(/0[xX]/),
            tag_as: "keyword.other.unit.hexadecimal",
            )
        octal_prefix = Pattern.new(
            should_fully_match: ["0"],
            should_partial_match: ["01234"],
            match: Pattern.new(/\G/).then(/0/),
            tag_as: "keyword.other.unit.octal",
            )
        binary_prefix = Pattern.new(
            should_fully_match: ["0b", "0B"],
            should_partial_match: ["0b1001"],
            should_not_partial_match: ["0x010b"],
            match: Pattern.new(/\G/).then(/0[bB]/),
            tag_as: "keyword.other.unit.binary",
            )
        decimal_prefix = Pattern.new(
            should_partial_match: ["1234"],
            match: Pattern.new(/\G/).lookAheadFor(/[0-9.]/).lookAheadToAvoid(/0[xXbB]/),
            )
        numeric_suffix = Pattern.new(
            should_fully_match: ["u","l","UL","llU"],
            should_not_fully_match: ["lLu","uU","lug"],
            match: Pattern.new(/[uU]/).or(/[uU]ll?/).or(/[uU]LL?/).or(/ll?[uU]?/).or(/LL?[uU]?/).or(/[fF]/).lookAheadToAvoid(/\w/),
            tag_as: "keyword.other.unit.suffix.integer",
            )

        # see https://en.cppreference.com/w/cpp/language/floating_literal
        hex_exponent = Pattern.new(
            should_fully_match: [ "p100", "p-100", "p+100", "P100" ],
            should_not_fully_match: [ "p0x0", "p-+100" ],
            match: lookBehindToAvoid(/#{separator}/).then(
                    match: /[pP]/,
                    tag_as: "keyword.other.unit.exponent.hexadecimal",
                ).maybe(
                    match: /\+/,
                    tag_as: "keyword.operator.plus.exponent.hexadecimal",
                ).maybe(
                    match: /\-/,
                    tag_as: "keyword.operator.minus.exponent.hexadecimal",
                ).then(
                    match: decimal_digits.groupless,
                    tag_as: "constant.numeric.exponent.hexadecimal",
                    includes: [ number_separator_pattern ]
                ),
            )
        decimal_exponent = Pattern.new(
            should_fully_match: [ "e100", "e-100", "e+100", "E100", ],
            should_not_fully_match: [ "e0x0", "e-+100" ],
            match: lookBehindToAvoid(/#{separator}/).then(
                    match: /[eE]/,
                    tag_as: "keyword.other.unit.exponent.decimal",
                ).maybe(
                    match: /\+/,
                    tag_as: "keyword.operator.plus.exponent.decimal",
                ).maybe(
                    match: /\-/,
                    tag_as: "keyword.operator.minus.exponent.decimal",
                ).then(
                    match: decimal_digits.groupless,
                    tag_as: "constant.numeric.exponent.decimal",
                    includes: [ number_separator_pattern ]
                ),
            )
        hex_point = Pattern.new(
            # lookBehind/Ahead because there needs to be a hex digit on at least one side
            match: lookBehindFor(/[0-9a-fA-F]/).then(/\./).or(Pattern.new(/\./).lookAheadFor(/[0-9a-fA-F]/)),
            tag_as: "constant.numeric.hexadecimal",
            )
        decimal_point = Pattern.new(
            # lookBehind/Ahead because there needs to be a decimal digit on at least one side
            match: lookBehindFor(/[0-9]/).then(/\./).or(Pattern.new(/\./).lookAheadFor(/[0-9]/)),
            tag_as: "constant.numeric.decimal.point",
            )
        floating_suffix = Pattern.new(
            should_fully_match: ["f","l","L","F"],
            should_not_fully_match: ["lLu","uU","lug","fan"],
            match: Pattern.new(/[lLfF]/).lookAheadToAvoid(/\w/),
            tag_as: "keyword.other.unit.suffix.floating-point"
            )
        
        
        hex_ending = end_pattern
        decimal_ending = end_pattern
        binary_ending = end_pattern
        octal_ending = end_pattern
        
        decimal_user_defined_literal_pattern = Pattern.new(
                match: maybe(Pattern.new(/\w/).lookBehindToAvoid(/[0-9eE]/).then(/\w*/)).then(end_pattern),
                tag_as: "keyword.other.unit.user-defined"
            )
        hex_user_defined_literal_pattern = Pattern.new(
                match: maybe(Pattern.new(/\w/).lookBehindToAvoid(/[0-9a-fA-FpP]/).then(/\w*/)).then(end_pattern),
                tag_as: "keyword.other.unit.user-defined"
            )
        normal_user_defined_literal_pattern = Pattern.new(
                match: maybe(Pattern.new(/\w/).lookBehindToAvoid(/[0-9]/).then(/\w*/)).then(end_pattern),
                tag_as: "keyword.other.unit.user-defined"
            )
        
        if allow_user_defined_literals
            hex_ending     = hex_user_defined_literal_pattern
            decimal_ending = decimal_user_defined_literal_pattern
            binary_ending  = normal_user_defined_literal_pattern
            octal_ending   = normal_user_defined_literal_pattern
        end

        # 
        # How this works
        # 
        # first a range (the whole number) is found
        # then, after the range is found, it starts to figure out what kind of number/constant it is
        # it does this by matching one of the includes
        return Pattern.new(
            match: lookBehindToAvoid(/\w/).then(/\.?\d/).zeroOrMoreOf(valid_character),
            includes: [
                PatternRange.new(
                    start_pattern: lookAheadFor(/./),
                    end_pattern: end_pattern,
                    # only a single include pattern should match
                    includes: [
                        # floating point
                        hex_prefix    .maybe(hex_digits    ).then(hex_point    ).maybe(hex_digits    ).maybe(hex_exponent    ).maybe(floating_suffix).then(hex_ending),
                        decimal_prefix.maybe(decimal_digits).then(decimal_point).maybe(decimal_digits).maybe(decimal_exponent).maybe(floating_suffix).then(decimal_ending),
                        # numeric
                        binary_prefix .then(binary_digits )                        .maybe(numeric_suffix).then(binary_ending ),
                        octal_prefix  .then(octal_digits  )                        .maybe(numeric_suffix).then(octal_ending  ),
                        hex_prefix    .then(hex_digits    ).maybe(hex_exponent    ).maybe(numeric_suffix).then(hex_ending    ),
                        decimal_prefix.then(decimal_digits).maybe(decimal_exponent).maybe(numeric_suffix).then(decimal_ending),
                        # invalid
                        Pattern.new(
                            match: oneOrMoreOf(Pattern.new(valid_single_character).or(valid_after_exponent)),
                            tag_as: "invalid.illegal.constant.numeric"
                        )
                    ]
                )
            ]
        )
    end
    
    def c_style_control(keyword:"", primary_inlcudes:[],  parentheses_include:[], body_includes:[], secondary_includes:[])
        PatternRange.new(
            start_pattern: Pattern.new(
                Pattern.new(/\s*+/).then(
                    match: lookBehindToAvoid(@standard_character).then(/#{keyword}/).lookAheadToAvoid(@standard_character),
                    tag_as: "keyword.control.#{keyword}"
                ).then(/\s*+/)
            ),
            end_pattern: Pattern.new(
                match: Pattern.new(
                    match: /;/,
                    tag_as: "punctuation.terminator.statement"
                ).or(
                    match: /\}/,
                    tag_as: "punctuation.section.block.control"
                )
            ),
            includes: [
                *primary_inlcudes,
                PatternRange.new(
                    tag_content_as: "meta.control.evaluation.perl", # this ".perl" is a workaround for a bug in ruby_grammar_builder
                    start_pattern: Pattern.new(
                        match: /\(/,
                        tag_as: "punctuation.section.parens.control",
                    ),
                    end_pattern: Pattern.new(
                        match: /\)/,
                        tag_as: "punctuation.section.parens.control",
                    ),
                    includes: parentheses_include
                ),
                PatternRange.new(
                    tag_content_as: "meta.control.body.perl", # this ".perl" is a workaround for a bug in ruby_grammar_builder
                    start_pattern: Pattern.new(
                        match: /\{/,
                        tag_as: "punctuation.section.block.control"
                    ),
                    end_pattern: lookAheadFor(/\}/),
                    includes: body_includes
                ),
                *secondary_includes
            ]
        )
    end

    
# 
# utils
# 
    # NOTE: this pattern can match 0-spaces so long as its still a word boundary
    # std_space = Pattern.new(
    #     Pattern.new(
    #         at_least: 1,
    #         quantity_preference: :as_few_as_possible,
    #         match: Pattern.new(
    #                 match: @spaces,
    #                 dont_back_track?: true
    #             )
    #     # zero length match
    #     ).or(
    #         Pattern.new(/\b/).or(
    #             lookBehindFor(/\W/)
    #         ).or(
    #             lookAheadFor(/\W/)
    #         ).or(
    #             @start_of_document
    #         ).or(
    #             @end_of_document
    #         )
    #     )
    # )
    # equivlent to above, but with less generated wrappers (more optimized)
    std_space = /(?>\s+)+?|\b|(?<=\W)|(?=\W)|\A|\Z/
#
#
# Contexts
#
#
    grammar[:$initial_context] = [
            :using_statement,
            :control_flow,
            :function_definition,
            :function_call,
            :label,
            :numbers,
            :inline_regex,
            :special_identifiers,
            :keyword_operators,
            :storage_declares,
            :line_comment,
            :block_comment,
            :variable,
            
            # all the originals from "modified.tmLanguage.json"
            :anon_pattern_1,
            :anon_pattern_2,
            :anon_pattern_3,
            :anon_pattern_4,
            :anon_pattern_5,
            :anon_pattern_6,
            :anon_pattern_7,
            :anon_pattern_8,
            :anon_pattern_9,
            :anon_pattern_10,
            :anon_pattern_11,
            :anon_pattern_12,
            :anon_pattern_13,
            :anon_pattern_14,
            :anon_pattern_15,
            :anon_pattern_16,
            :anon_pattern_17,
            :anon_pattern_18,
            :anon_pattern_19,
            :anon_pattern_20,
            :anon_pattern_21,
            :anon_pattern_22,
            :anon_pattern_23,
            :anon_pattern_24,
            :anon_pattern_25,
            :anon_pattern_26,
            :anon_pattern_27,
            :anon_pattern_28,
            :anon_pattern_29,
            :anon_pattern_30,
            :anon_pattern_31,
            :anon_pattern_32,
            :anon_pattern_33,
            :anon_pattern_34,
            :anon_pattern_35,
            :anon_pattern_36,
            :anon_pattern_37,
            :anon_pattern_38,
            :anon_pattern_39,
            :anon_pattern_40,
            :anon_pattern_41,
            :anon_pattern_42,
            :anon_pattern_43,
            :anon_pattern_44,
            :anon_pattern_45,
            :anon_pattern_46,
            :anon_pattern_47,
            :anon_pattern_48,
            :anon_pattern_49,
            :anon_pattern_50,
            :anon_pattern_51,
            :anon_pattern_52,
            :anon_pattern_53,
            :anon_pattern_54,
            :anon_pattern_55,
            :anon_pattern_56,
            :anon_pattern_57,
            :anon_pattern_58,
            :anon_pattern_59,
            :anon_pattern_60,
            :anon_pattern_61,
            :anon_pattern_62,
            :anon_pattern_63,
            :anon_pattern_64,
            :anon_pattern_65,
            :anon_pattern_66,
            :anon_pattern_67,
            
            :operators,
            :punctuation,
        ]
#
#
# Patterns
#
#
    # 
    # comment
    # 
        # {
        # 		"begin": "^(?==[a-zA-Z]+)",
        # 		"end": "^(=cut\\b.*$)",
        # 		"endCaptures": {
        # 			"1": {
        # 				"patterns": [
        # 					{
        # 						"include": "#pod"
        # 					}
        # 				]
        # 			}
        # 		},
        # 		"name": "comment.block.documentation.perl",
        # 		"patterns": [
        # 			{
        # 				"include": "#pod"
        # 			}
        # 		]
        # }
    grammar[:block_comment] = PatternRange.new(
        tag_as: "comment.block.documentation.perl",
        start_pattern: Pattern.new(
            match: /^(?==[a-zA-Z]+)/,
        ),
        end_pattern: Pattern.new(
            match: /^(?:=cut\b.*$)/,
            includes: [
                :pod,
            ]
        ),
        includes: [
            :pod,
        ],
    )
    # 
    # numbers
    # 
        grammar[:numbers] = numeric_constant(separator:"_")
    # 
    # regex
    # 
        grammar[:inline_regex] = Pattern.new(std_space).then(
            Pattern.new(
                match: /\//,
                tag_as: "punctuation.section.regexp"
            ).then(
                match: zeroOrMoreOf(
                    match: /[^\/\\]|\\./,
                    dont_back_track?: true,
                ),
                tag_as: "string.regexp",
                includes: [ :regexp ],
            ).then(
                match: /\//,
                tag_as: "punctuation.section.regexp"
            )
        )
    # 
    # builtins
    # 
        grammar[:special_identifiers] = [
            Pattern.new(
                match: /\$\^[A-Z^_?\[\]]/,
                tag_as: "variable.language.special.caret"
            ),
            Pattern.new(
                match: variableBounds[/undef/],
                tag_as: "constant.language.undef",
            )
        ]
            
    # 
    # operators
    # 
        grammar[:keyword_operators]  = [
            Pattern.new(
                match: variableBounds[@tokens.that(:areOperatorAliases)],
                tag_as: "keyword.operator.alias.$match",
            ),
        ]
        grammar[:operators] = [
            PatternRange.new(
                tag_content_as: "meta.readline.perl", # this ".perl" is a workaround for a bug in ruby_grammar_builder
                start_pattern: Pattern.new(
                    lookBehindToAvoid(/\s|\w|</).then(std_space).then(
                        match: /</,
                        tag_as: "punctuation.separator.readline",
                    ).lookAheadToAvoid(/<|\=/)
                ),
                end_pattern: Pattern.new(
                    match: />/,
                    tag_as:"punctuation.separator.readline",
                ),
                includes: [ :$initial_context ]
            ),
            Pattern.new(
                match: @tokens.that(:areComparisonOperators, not(:areOperatorAliases)),
                tag_as: "keyword.operator.comparison",
            ),
            Pattern.new(
                match: @tokens.that(:areAssignmentOperators, not(:areOperatorAliases)),
                tag_as: "keyword.operator.assignment",
            ),
            Pattern.new(
                match: @tokens.that(:areLogicalOperators, not(:areOperatorAliases)),
                tag_as: "keyword.operator.logical",
            ),
            Pattern.new(
                match: @tokens.that(:areArithmeticOperators, not(:areAssignmentOperators), not(:areOperatorAliases)),
                tag_as: "keyword.operator.arithmetic",
            ),
            Pattern.new(
                match: @tokens.that(:areBitwiseOperators, not(:areAssignmentOperators), not(:areOperatorAliases)),
                tag_as: "keyword.operator.bitwise",
            ),
            Pattern.new(
                match: @tokens.that(:areOperators, not(:areOperatorAliases)),
                tag_as: "keyword.operator",
            ),
        ]
    # 
    # state
    # 
        grammar[:storage_declares] = Pattern.new(
            match: /\b(?:my|our|local|state)\b/,
            tag_as: "storage.modifier.$match",
        )
    # 
    # punctuation
    # 
        grammar[:semicolon] = Pattern.new(
            match: /;/,
            tag_as: "punctuation.terminator.statement"
        )
        grammar[:comma] = Pattern.new(
            match: /,/,
            tag_as: "punctuation.separator.comma"
        )
        # unknown/other
        grammar[:square_brackets] = PatternRange.new(
            start_pattern: Pattern.new(
                match: /\[/,
                tag_as: "punctuation.section.square-brackets",
            ),
            end_pattern: Pattern.new(
                match: /\]/,
                tag_as: "punctuation.section.square-brackets",
            ),
            includes: [ :$initial_context ]
        )
        grammar[:curly_brackets] = PatternRange.new(
            start_pattern: Pattern.new(
                match: /\{/,
                tag_as: "punctuation.section.curly-brackets",
            ),
            end_pattern: Pattern.new(
                match: /\}/,
                tag_as: "punctuation.section.curly-brackets",
            ),
            includes: [ :$initial_context ]
        )
        grammar[:parentheses] = PatternRange.new(
            start_pattern: Pattern.new(
                match: /\(/,
                tag_as: "punctuation.section.parens",
            ),
            end_pattern: Pattern.new(
                match: /\)/,
                tag_as: "punctuation.section.parens",
            ),
            includes: [ :$initial_context ]
        )
        grammar[:punctuation] = [
            :semicolon,
            :comma,
            :square_brackets,
            :curly_brackets,
            :parentheses,
        ]
    # 
    # imports
    # 
        grammar[:using_statement] = PatternRange.new(
            tag_as: "meta.import",
            start_pattern: Pattern.new(
                Pattern.new(
                    match: /use/,
                    tag_as: "keyword.other.use"
                ).then(std_space).then(
                    match: /[\w\.]+/,
                    tag_as: "entity.name.package",
                )
            ),
            end_pattern: grammar[:semicolon],
            includes: [
                Pattern.new(
                    match: /::/,
                    tag_as: "punctuation.separator.resolution"
                ),
                # qw()
                PatternRange.new(
                    start_pattern: Pattern.new(
                        Pattern.new(
                            match: /qw/,
                            tag_as: "entity.name.function.special"
                        ).then(std_space).then(
                            match: /\(/,
                            tag_as: "punctuation.section.block.function.special",
                        )
                    ),
                    end_pattern: Pattern.new(
                        match: /\)/,
                        tag_as: "punctuation.section.block.function.special",
                    ),
                    includes: [
                        :variable
                    ]
                ),
            ]
        )
    # 
    # control flow
    # 
        grammar[:control_flow] = [
            :if_statement,
            :elsif_statement,
            :else_statement,
            :while_statement,
            :for_statement,
        ]
        grammar[:if_statement]    = c_style_control(keyword:"if"    , parentheses_include:[ :$initial_context ], body_includes:[ :$initial_context ], secondary_includes:[:$initial_context])
        grammar[:elsif_statement] = c_style_control(keyword:"elsif" , parentheses_include:[ :$initial_context ], body_includes:[ :$initial_context ], secondary_includes:[:$initial_context])
        grammar[:else_statement]  = c_style_control(keyword:"else"  , parentheses_include:[ :$initial_context ], body_includes:[ :$initial_context ], secondary_includes:[:$initial_context])
        grammar[:while_statement] = c_style_control(keyword:"while" , parentheses_include:[ :$initial_context ], body_includes:[ :$initial_context ], secondary_includes:[:$initial_context])
        grammar[:for_statement]   = c_style_control(keyword:"for"   , parentheses_include:[ :$initial_context ], body_includes:[ :$initial_context ], secondary_includes:[:$initial_context])
    # 
    # function definition
    # 
        # see https://perldoc.perl.org/perlsub.html
        grammar[:parameters] = PatternRange.new(
            start_pattern: Pattern.new(
                match: /\(/,
                tag_as: "punctuation.section.parameters",
            ),
            end_pattern: Pattern.new(
                match: /\)/,
                tag_as: "punctuation.section.parameters",
            ),
            includes: [ :$initial_context ]
        )
        grammar[:function_definition] = PatternRange.new(
            start_pattern: Pattern.new(
                Pattern.new(
                    match: /sub/,
                    tag_as: "storage.type.sub",
                ).then(std_space).maybe(
                    match: @variable,
                    tag_as: "entity.name.function.definition",
                )
            ),
            end_pattern: Pattern.new(
                Pattern.new(
                    match: /\}/,
                    tag_as: "punctuation.section.block.function",
                ).or(
                    grammar[:semicolon]
                )
            ),
            includes: [
                PatternRange.new(
                    start_pattern: Pattern.new(
                        match: /\{/,
                        tag_as: "punctuation.section.block.function",  
                    ),
                    end_pattern: lookAheadFor(/\}/),
                    includes: [ 
                        :$initial_context 
                    ],
                ),
                :parameters,
                Pattern.new(
                    Pattern.new(
                        match: /:/,
                        tag_as: "punctuation.definition.attribute entity.name.attribute"
                    ).then(std_space).then(
                        match: @variable,
                        tag_as: "entity.name.attribute",
                    ).then(std_space)
                ),
                # todo: make this more restrictive 
                :$initial_context
            ]
        )
        grammar[:function_call] = PatternRange.new(
            start_pattern: Pattern.new(
                Pattern.new(
                    match: @variable,
                    tag_as: "entity.name.function.call",
                    word_cannot_be_any_of: ["qq", "qw", "q", "m", "qr", "s" , "tr", "y"], # see https://perldoc.perl.org/perlop.html#Quote-and-Quote-like-Operators
                ).then(std_space).then(
                    match: /\(/,
                    tag_as: "punctuation.section.arguments",
                )
            ),
            end_pattern: Pattern.new(
                match: /\)/,
                tag_as: "punctuation.section.arguments",
            ),
            includes: [ :$initial_context ]
        )
    # 
    # Labels
    # 
        grammar[:label] = Pattern.new(
            Pattern.new(/^/).then(std_space).then(
                tag_as: "entity.name.label",
                match: @variable,
            ).then(@word_boundary).then(
                std_space
            ).then(
                match: Pattern.new(/:/).lookAheadToAvoid(/:/),
                tag_as: "punctuation.separator.label",
            )
        )
    # 
    # copy over all the repos
    # 
        # for each_key, each_value in original_grammar["repository"]
        #     grammar[each_key.to_sym] = each_value
        # end
 
#
# Save
#
name = "perl"
dir = "./syntaxes"
Dir.mkdir(dir) unless File.exist?(dir)
grammar.save_to(
    syntax_name: name,
    syntax_dir: dir,
    tag_dir: dir,
)
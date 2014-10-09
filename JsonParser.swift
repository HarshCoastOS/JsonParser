//
// JsonParser.swift
// --------------------------------------------------------------------------------------
// Copyright (c)2014 Harsh Coast.
//
// The MIT License (MIT)
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// 


import Cocoa


/// The format of the JSON parser
///
enum JsonParserFormat {
    
    /// The standart format as specified here http://json.org/
    ///
    case StandartFormat
    
    /// An extended version of the JSON format which can include binary data
    ///
    case ExtendedFormat
}


/// A special JSON parser which supports all EducateIT extensions.
///
class JsonParser {
   
    /// The format for the parser.
    ///
    /// ExtendedFormat also allows a <...> tag with hex bytes for binary data.
    /// Actually the binary encoded objects are QVariant objects from the Qt library.
    ///
    var format = JsonParserFormat.StandartFormat
    
    /// Create a new parser
    ///
    init() {
    }
    
    /// Create a new parser with a given format
    ///
    init(format: JsonParserFormat) {
        self.format = format
    }
    
    /// Parse the given data object, assuming UTF-8 format.
    ///
    /// :param: data The data stream.
    /// :return: The root object, or nil on any error.
    ///
    func parse(#data: NSData)->(result: AnyObject?, error: JsonParserError?) {
        var str: String = NSString(data: data, encoding: NSUTF8StringEncoding)!
        return parse(string: str)
    }
    
    /// Parse the given string.
    ///
    /// :param: str The string to parse.
    /// :return: The root object, or nil on any error.
    ///
    func parse(#string: String)->(result: AnyObject?, error: JsonParserError?) {
        var state = JsonParserState(string: string, format: self.format)
        return state.parse()
    }
}


/// A error message
///
struct JsonParserError {
    var message: String
    var index: Int
    var line: Int
    var column: Int
    
    /// Create a new error object using the parser state
    ///
    private init(message: String, state: JsonParserState) {
        self.message = message
        self.index = state.currentIndex
        self.line = state.currentLine
        self.column = state.currentColumn
    }
}


/// The private state of the parser
///
private class JsonParserState {
    
    /// Character index.
    ///
    var currentIndex: Int = 0
    
    /// Current line
    ///
    var currentLine: Int = 0
    
    /// Current column.
    ///
    var currentColumn: Int = 0
    
    /// An already read character from the stream, we put back.
    ///
    private var thePutBackChar: Character? = nil
    
    /// A permanent token buffer.
    ///
    private var tokenBuffer: String = ""
    
    /// The string as array
    ///
    private let characterArray: Array<Character>

    /// The format of the JSON string
    ///
    private let format: JsonParserFormat
    
    /// Init the state with a given string
    ///
    init(string: String, format: JsonParserFormat) {
        self.characterArray = Array(string)
        self.format = format
    }
    
    /// Parse a JSON structure
    ///
    func parse() -> (result: AnyObject?, error: JsonParserError?) {
        
        // Parse exact one value.
        let (result: AnyObject?, error) = parseValue()
        
        // Got no value = error
        if result == nil {
            assert(error != nil, "Expected error object.")
            return (nil, error)
        }
        
        // Expect end of stream after the parsed value.
        skipWhitespace()
        if !atEnd() {
            return (nil, JsonParserError(message: "Expected end of string after value.", state: self))
        }
        
        return (result, nil) // Success
    }
    
    /// Parse a JSON value.
    ///
    func parseValue() -> (value: AnyObject?, error: JsonParserError?) {
        skipWhitespace()
        if atEnd() {
            return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
        }
        let c = readNextCharacter()
        switch c {
        case UC_DOUBLEQUOTE: // we got a string
            let (value, error) = parseString()
            return (value, error)
        case UC_LEFT_SQUARE_BRACKET: // we got an array
            return parseArray()
        case UC_LEFT_CURLY_BRACKET: // we got an object.
            let (value: AnyObject?, error) = parseObject()
            return (value, error)
        case UC_LESS_THAN_SIGN: // we got a binary encoded value
            if format == .ExtendedFormat {
                return parseBinary()
            } else {
                return (nil, JsonParserError(message: "Expected value, got character which does not fit any value.", state: self))
            }
        case UC_t: // has to be "true"
            if !assumeFollowup("rue") {
                return (nil, JsonParserError(message: "Expected value \"true\".", state: self))
            }
            return (NSNumber(bool: true), nil)
        case UC_f: // has to be "false"
            if !assumeFollowup("alse") {
                return (nil, JsonParserError(message: "Expected value \"false\".", state: self))
            }
            return (NSNumber(bool: false), nil)
        case UC_n: // has to be "null"
            if !assumeFollowup("ull") {
                return (nil, JsonParserError(message: "Expected value \"null\".", state: self))
            }
            return (NSNull(), nil)
        case UC_0, UC_1, UC_2, UC_3, UC_4, UC_5, UC_6, UC_7, UC_8, UC_9, UC_MINUS:
            putCharBack(c)
            let (value, isDouble, error) = parseNumber()
            if value == nil {
                return (nil, error)
            }
            let scanner = NSScanner(string: value!)
            if isDouble {
                // we assume a double.
                var doubleValue: Double = 0.0
                if !scanner.scanDouble(&doubleValue) {
                    return (nil, JsonParserError(message: "Syntax error in double number value.", state: self))
                }
                return (NSNumber(double: doubleValue), nil)
            } else {
                // we go for the largest possible number.
                var intValue: Int64 = 0
                if !scanner.scanLongLong(&intValue) {
                    return (nil, JsonParserError(message: "Syntax error in integer number value.", state: self))
                }
                return (NSNumber(longLong: intValue), nil)
            }
            
        default:
            // Bad syntax.
            return (nil, JsonParserError(message: "Expected value, got character which does not fit any value.", state: self))
        }
    }
    
    /// Parse a number.
    ///
    func parseNumber() -> (string: String?, isDouble: Bool, error: JsonParserError?) {
        var isDouble = false
        tokenBuffer = ""
        var c = readNextCharacter()
        while isNumberChar(c) {
            if c == UC_E || c == UC_e || c == UC_FULL_STOP {
                isDouble = true
            }
            tokenBuffer.append(c)
            if countElements(tokenBuffer) > 256 { // limit token size.
                return (nil, false, JsonParserError(message: "Expected number, but got text which exceeds number length limit.", state: self))
            }
            if atEnd() {
                return (tokenBuffer, isDouble, nil)
            }
            c = readNextCharacter()
        }
        putCharBack(c) // put back the non number character.
        return (tokenBuffer, isDouble, nil)
    }
    
    /// Parse a string.
    ///
    func parseString() -> (string: String?, error: JsonParserError?) {
        // Initial " character is already consumed.
        tokenBuffer = ""
        if atEnd() {
            return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
        }
        var c = readNextCharacter()
        while c != UC_DOUBLEQUOTE {
            if c < UC_SPACE {
                return (nil, JsonParserError(message: "Control characters are not allowed in strings.", state: self))
            } else if c == UC_REVERSE_SOLIDUS {
                if atEnd() {
                    return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
                }
                c = readNextCharacter()
                switch c {
                case UC_REVERSE_SOLIDUS, UC_SOLIDUS, UC_DOUBLEQUOTE:
                    tokenBuffer.append(c)
                case UC_b:
                    tokenBuffer.append(UC_BACKSPACE)
                case UC_f:
                    tokenBuffer.append(UC_FORM_FEED)
                case UC_n:
                    tokenBuffer.append(UC_NEWLINE)
                case UC_r:
                    tokenBuffer.append(UC_CARRIAGE_RETURN)
                case UC_t:
                    tokenBuffer.append(UC_TAB)
                case UC_u:
                    var hexValue = ""
                    for i in 0...3 {
                        if atEnd() {
                            return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
                        }
                        c = readNextCharacter()
                        if !isHexChar(c) {
                            return (nil, JsonParserError(message: "Read unexpected char. Expected a hex value.", state: self))
                        }
                        hexValue.append(c)
                    }
                    var scanner = NSScanner(string: hexValue)
                    var value: UInt32 = 0
                    if (scanner.scanHexInt(&value)) {
                        return (nil, JsonParserError(message: "Could not parse hex string for unicode.", state: self))
                    }
                    tokenBuffer.append(UnicodeScalar(value))
                default:
                    return (nil, JsonParserError(message: "Read unexpected char. Unknown escape character.", state: self))
                }
            } else {
                tokenBuffer.append(c)
            }
            if atEnd() {
                return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
            }
            c = readNextCharacter()
        }
        
        // return successful with the string.
        return (tokenBuffer, nil)
    }
    
    /// Parse a binary data element (extended format).
    ///
    func parseBinary() -> (value: AnyObject?, error: JsonParserError?) {
        // Initial < character is already consumed.
        tokenBuffer = ""
        if atEnd() {
            return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
        }
        var c = readNextCharacter()
        // Read until we get the > character.
        while c != UC_GREATER_THAN_SIGN {
            if !isBase64Char(c) {
                return (nil, JsonParserError(message: "Binary value contains other chars which are not allowed in Base64 encoding.", state: self))
            } else {
                tokenBuffer.append(c)
            }
            if atEnd() {
                return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
            }
            c = readNextCharacter()
        }
        // Decode the buffer.
        let data = NSData(base64EncodedString: tokenBuffer, options: NSDataBase64DecodingOptions.IgnoreUnknownCharacters)
        // TODO: Decode the QVariant value from the buffer.
        // Actually this isn't done in this implementation. Instead the
        // raw NSData object is returned.
        return (data, nil)
    }
    
    /// Parse an array.
    ///
    func parseArray() -> (value: AnyObject?, error: JsonParserError?) {
        // Initial [ character is already consumed.
        var result = Array<AnyObject>()
        // skip initial whitespace and check for empty array.
        skipWhitespace()
        if atEnd() {
            return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
        }
        var c = readNextCharacter()
        if c == UC_RIGHT_SQUARE_BRACKET { // empty list
            return (result, nil)
        }
        // it is not an empty list, expect a value now.
        putCharBack(c)
        // loop over the values
        do {
            let (value: AnyObject?, error) = parseValue()
            if (value == nil) {
                return (nil, error)
            }
            result.append(value!)
            skipWhitespace()
            if atEnd() {
                return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
            }
            c = readNextCharacter()
            if c == UC_RIGHT_SQUARE_BRACKET { // end of list.
                break
            } else if c != UC_COMMA {
                return (nil, JsonParserError(message: "Read unexpected character. Expected ',' or ']' character.", state: self))
            }
            skipWhitespace()
            if atEnd() {
                return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
            }
        } while c == UC_COMMA
        
        // successfully reached the end of the array
        return (result, nil)
    }
    
    /// Parse an object.
    ///
    func parseObject() -> (value: AnyObject?, error: JsonParserError?) {
        // Initial { character is already consumed.
        var result = Dictionary<String, AnyObject>()
        // skip initial whitespace and check for empty object.
        skipWhitespace()
        if atEnd() {
            return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
        }
        var c = readNextCharacter()
        if c == UC_RIGHT_CURLY_BRACKET { // reached end of object.
            return (result, nil)
        }
        // ok it isn't empty.
        putCharBack(c)
        // loop over the values.
        do {
            skipWhitespace()
            if atEnd() {
                return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
            }
            c = readNextCharacter()
            if c != UC_DOUBLEQUOTE { // expect a string.
                return (nil, JsonParserError(message: "Read unexpected character. Expected begin of a string.", state: self))
            }
            let (key, keyError) = parseString()
            if (key == nil) {
                return (nil, keyError)
            }
            skipWhitespace()
            if atEnd() {
                return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
            }
            c = readNextCharacter()
            if c != UC_COLON {
                return (nil, JsonParserError(message: "Read unexpected character. Expected ':' character.", state: self))
            }
            skipWhitespace()
            if atEnd() {
                return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
            }
            let (value: AnyObject?, valueError) = parseValue()
            if (value == nil) {
                return (nil, valueError)
            }
            result[key!] = value!
            skipWhitespace()
            if atEnd() {
                return (nil, JsonParserError(message: EM_ExpectedMore, state: self))
            }
            c = readNextCharacter()
            if c != UC_RIGHT_CURLY_BRACKET && c != UC_COMMA {
                return (nil, JsonParserError(message: "Read unexpected character. Expected ',' or '}' character.", state: self))
            }
        } while c == UC_COMMA
        
        // successfully reached the end of the object
        return (result, nil)
    }
    
    /// Assumes an exact followup.
    ///
    /// :return: false if this followup doesn't match.
    ///
    private func assumeFollowup(followup: String) -> Bool {
        for expectedCharacter in followup {
            let c = readNextCharacter()
            if c != expectedCharacter {
                return false
            }
        }
        return true
    }
    
    /// Return the next character in the string.
    ///
    private func readNextCharacter() -> Character {
        // Return the put back character if there is one.
        if thePutBackChar != nil {
            let c = thePutBackChar!
            thePutBackChar = nil
            return c
        }

        // Get the character and increase counter
        assert(currentIndex < characterArray.count, "Index out of range")
        let c = characterArray[currentIndex]
        ++currentIndex
        ++currentColumn
        
        // Check for newlines.
        if c == UC_NEWLINE {
            ++currentLine
            currentColumn = 0
        }

        return c
    }

    /// Skip any whitespace
    ///
    private func skipWhitespace() {
        if atEnd() {
            return
        }
        var c = readNextCharacter()
        while isWhitespace(c) {
            if atEnd() {
                return
            }
            c = readNextCharacter()
        }
        putCharBack(c)
    }
    
    /// Put a read character back into the stream.
    ///
    private func putCharBack(character: Character) {
        assert(thePutBackChar == nil, "There is already a put back character")
        thePutBackChar = character
    }
    
    /// Check if a character is whitespace
    ///
    private func isWhitespace(character: Character) -> Bool {
        return character == UC_NEWLINE ||
            character == UC_CARRIAGE_RETURN ||
            character == UC_TAB ||
            character == UC_SPACE
    }
    
    /// Check if a char is a digit
    ///
    private func isDigit(character: Character) -> Bool {
        return character >= UC_0 && character <= UC_9
    }
    
    /// Check if the char is a token char
    ///
    private func isNumberChar(character: Character) -> Bool {
        return isDigit(character) ||
            character == UC_PLUS ||
            character == UC_MINUS ||
            character == UC_FULL_STOP ||
            character == UC_E ||
            character == UC_e
    }
    
    /// Check if the char is a hexadecimal char.
    ///
    private func isHexChar(character: Character) -> Bool {
        return isDigit(character) ||
            (character >= UC_a && character <= UC_f) ||
            (character >= UC_A && character <= UC_F)
    }
    
    /// Check if the char is allowed in Base64 encoding.
    ///
    private func isBase64Char(character: Character) -> Bool {
        return character == UC_PLUS ||
            character == UC_SOLIDUS ||
            character == UC_EQUAL_SIGN ||
            (character >= UC_0 && character <= UC_9) ||
            (character >= UC_a && character <= UC_z) ||
            (character >= UC_A && character <= UC_Z)
    }
    
    /// Check if we are at the end of the string.
    /// Takes a put back character into account.
    ///
    private func atEnd() -> Bool {
        return thePutBackChar == nil && currentIndex >= characterArray.count
    }

    // Define all relevant unicode characters which are used in the parser.
    //
    private let UC_0: Character = "\u{30}"
    private let UC_1: Character = "\u{31}"
    private let UC_2: Character = "\u{32}"
    private let UC_3: Character = "\u{33}"
    private let UC_4: Character = "\u{34}"
    private let UC_5: Character = "\u{35}"
    private let UC_6: Character = "\u{36}"
    private let UC_7: Character = "\u{37}"
    private let UC_8: Character = "\u{38}"
    private let UC_9: Character = "\u{39}"
    private let UC_A: Character = "\u{41}"
    private let UC_BACKSPACE: Character = "\u{08}"
    private let UC_CARRIAGE_RETURN: Character = "\u{0D}"
    private let UC_COLON: Character = "\u{3A}"
    private let UC_COMMA: Character = "\u{2C}"
    private let UC_DOUBLEQUOTE: Character = "\u{22}"
    private let UC_E: Character = "\u{45}"
    private let UC_EQUAL_SIGN: Character = "\u{3D}"
    private let UC_F: Character = "\u{46}"
    private let UC_FORM_FEED: Character = "\u{0C}"
    private let UC_FULL_STOP: Character = "\u{2E}"
    private let UC_GREATER_THAN_SIGN: Character = "\u{3E}"
    private let UC_LEFT_CURLY_BRACKET: Character = "\u{7B}"
    private let UC_LEFT_SQUARE_BRACKET: Character = "\u{5B}"
    private let UC_LESS_THAN_SIGN: Character = "\u{3C}"
    private let UC_MINUS: Character = "\u{2D}"
    private let UC_NEWLINE: Character = "\u{0A}"
    private let UC_PLUS: Character = "\u{2B}"
    private let UC_REVERSE_SOLIDUS: Character = "\u{5C}"
    private let UC_RIGHT_CURLY_BRACKET: Character = "\u{7D}"
    private let UC_RIGHT_SQUARE_BRACKET: Character = "\u{5D}"
    private let UC_SOLIDUS: Character = "\u{2F}"
    private let UC_SPACE: Character = "\u{20}"
    private let UC_TAB: Character = "\u{09}"
    private let UC_Z: Character = "\u{5A}"
    private let UC_a: Character = "\u{61}"
    private let UC_b: Character = "\u{62}"
    private let UC_e: Character = "\u{65}"
    private let UC_f: Character = "\u{66}"
    private let UC_n: Character = "\u{6E}"
    private let UC_r: Character = "\u{72}"
    private let UC_t: Character = "\u{74}"
    private let UC_u: Character = "\u{75}"
    private let UC_z: Character = "\u{7A}"
    
    private let EM_ExpectedMore = "Expected more data, but reached end of data"
}



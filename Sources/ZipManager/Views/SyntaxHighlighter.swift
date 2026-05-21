import AppKit

// MARK: - Language

enum Language {
    case swift, python, javascript, typescript, rust, go, java, kotlin
    case c, cpp, ruby, php, shell, html, css, sql
    case json, xml, yaml, toml, markdown, csv, text, unknown

    static func from(ext: String) -> Language {
        switch ext.lowercased() {
        case "swift": return .swift
        case "py": return .python
        case "js", "jsx", "mjs": return .javascript
        case "ts", "tsx": return .typescript
        case "rs": return .rust
        case "go": return .go
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "c": return .c
        case "cpp", "cc", "cxx", "hpp", "h": return .cpp
        case "rb": return .ruby
        case "php": return .php
        case "sh", "bash", "zsh", "fish": return .shell
        case "html", "htm": return .html
        case "css", "scss", "sass", "less": return .css
        case "sql": return .sql
        case "json": return .json
        case "xml", "plist": return .xml
        case "yaml", "yml": return .yaml
        case "toml": return .toml
        case "md", "markdown": return .markdown
        case "csv", "tsv": return .csv
        default: return .text
        }
    }
}

// MARK: - SyntaxHighlighter

struct SyntaxHighlighter {

    // MARK: - Palette

    struct Colors {
        static let keyword    = NSColor(red: 0.80, green: 0.25, blue: 0.85, alpha: 1)
        static let string     = NSColor(red: 0.20, green: 0.70, blue: 0.30, alpha: 1)
        static let comment    = NSColor(red: 0.45, green: 0.55, blue: 0.45, alpha: 1)
        static let number     = NSColor(red: 0.20, green: 0.60, blue: 0.90, alpha: 1)
        static let type_      = NSColor(red: 0.40, green: 0.75, blue: 0.95, alpha: 1)
        static let function_  = NSColor(red: 0.65, green: 0.85, blue: 0.40, alpha: 1)
        static let operator_  = NSColor(red: 0.90, green: 0.55, blue: 0.25, alpha: 1)
        static let jsonKey    = NSColor(red: 0.90, green: 0.40, blue: 0.40, alpha: 1)
        static let xmlTag     = NSColor(red: 0.55, green: 0.80, blue: 0.95, alpha: 1)
        static let attr       = NSColor(red: 0.95, green: 0.75, blue: 0.35, alpha: 1)
        static let plain      = NSColor.labelColor
    }

    static let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

    // MARK: - Main entry

    static func highlight(_ source: String, language: Language) -> NSAttributedString {
        switch language {
        case .json: return highlightJSON(source)
        case .xml, .html: return highlightXML(source)
        case .markdown: return highlightMarkdown(source)
        case .csv: return plain(source)
        case .text, .unknown: return plain(source)
        default: return highlightCode(source, language: language)
        }
    }

    // MARK: - Generic code highlighter

    private static func highlightCode(_ source: String, language: Language) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseAttr: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: Colors.plain]

        let tokens = tokenize(source, language: language)
        for token in tokens {
            let color: NSColor
            switch token.kind {
            case .keyword: color = Colors.keyword
            case .string: color = Colors.string
            case .comment: color = Colors.comment
            case .number: color = Colors.number
            case .type_: color = Colors.type_
            case .function_: color = Colors.function_
            case .operator_: color = Colors.operator_
            case .plain: color = Colors.plain
            }
            var attrs = baseAttr
            attrs[.foregroundColor] = color
            if token.kind == .keyword { attrs[.font] = boldFont }
            result.append(NSAttributedString(string: token.text, attributes: attrs))
        }
        return result
    }

    // MARK: - JSON highlighter

    static func highlightJSON(_ source: String) -> NSAttributedString {
        let formatted: String
        if let data = source.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            formatted = str
        } else {
            formatted = source
        }

        let result = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: Colors.plain]

        let lines = formatted.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            appendJSONLine(line, to: result, baseAttr: base)
            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: base))
            }
        }
        return result
    }

    private static func appendJSONLine(_ line: String, to result: NSMutableAttributedString, baseAttr: [NSAttributedString.Key: Any]) {
        // Match: "key": value
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var consumed = 0

        // Leading whitespace
        let indent = line.prefix(while: { $0 == " " })
        result.append(NSAttributedString(string: String(indent), attributes: baseAttr))
        consumed = indent.count

        let rest = String(line.dropFirst(consumed))

        // Key detection: starts with "
        if rest.hasPrefix("\"") {
            if let colonRange = rest.range(of: "\": ") {
                let key = String(rest[..<colonRange.upperBound])
                let keyStr = String(rest[rest.startIndex..<colonRange.lowerBound]) + "\""
                var keyAttr = baseAttr; keyAttr[.foregroundColor] = Colors.jsonKey
                result.append(NSAttributedString(string: keyStr, attributes: keyAttr))
                result.append(NSAttributedString(string: ": ", attributes: baseAttr))
                let valueStr = String(rest[colonRange.upperBound...])
                appendJSONValue(valueStr, to: result, baseAttr: baseAttr)
                return
            }
        }
        // Standalone value or structural char
        appendJSONValue(rest, to: result, baseAttr: baseAttr)
    }

    private static func appendJSONValue(_ text: String, to result: NSMutableAttributedString, baseAttr: [NSAttributedString.Key: Any]) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        _ = text  // trailing comma detection handled inline

        func colored(_ color: NSColor, _ str: String) {
            var a = baseAttr; a[.foregroundColor] = color
            result.append(NSAttributedString(string: str, attributes: a))
        }

        if trimmed.hasPrefix("\"") {
            colored(Colors.string, text)
        } else if trimmed == "true" || trimmed == "false" || trimmed == "null"
               || trimmed == "true," || trimmed == "false," || trimmed == "null," {
            colored(Colors.operator_, text)
        } else if let firstChar = trimmed.first, firstChar.isNumber || firstChar == "-" {
            colored(Colors.number, text)
        } else {
            result.append(NSAttributedString(string: text, attributes: baseAttr))
        }
    }

    // MARK: - XML/HTML highlighter

    private static func highlightXML(_ source: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: Colors.plain]

        var idx = source.startIndex
        while idx < source.endIndex {
            if source[idx] == "<" {
                // Find closing >
                if let end = source[idx...].firstIndex(of: ">") {
                    let tagContent = String(source[idx...source.index(after: end)])
                    let inner = String(source[source.index(after: idx)..<end])
                    var tagAttr = base; tagAttr[.foregroundColor] = Colors.xmlTag
                    // Color tag name, attributes separately
                    result.append(NSAttributedString(string: "<", attributes: tagAttr))
                    let parts = inner.split(separator: " ", maxSplits: 1)
                    if let tagName = parts.first {
                        result.append(NSAttributedString(string: String(tagName), attributes: tagAttr))
                        if parts.count > 1 {
                            var attrAttr = base; attrAttr[.foregroundColor] = Colors.attr
                            result.append(NSAttributedString(string: " " + String(parts[1]), attributes: attrAttr))
                        }
                    }
                    result.append(NSAttributedString(string: ">", attributes: tagAttr))
                    idx = source.index(after: end)
                } else {
                    result.append(NSAttributedString(string: String(source[idx]), attributes: base))
                    idx = source.index(after: idx)
                }
            } else {
                // plain text until next <
                var end = idx
                while end < source.endIndex && source[end] != "<" {
                    end = source.index(after: end)
                }
                result.append(NSAttributedString(string: String(source[idx..<end]), attributes: base))
                idx = end
            }
        }
        return result
    }

    // MARK: - Markdown highlighter

    private static func highlightMarkdown(_ source: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: Colors.plain]
        for line in source.components(separatedBy: "\n") {
            if line.hasPrefix("# ") || line.hasPrefix("## ") || line.hasPrefix("### ") {
                var a = base; a[.font] = boldFont; a[.foregroundColor] = Colors.type_
                result.append(NSAttributedString(string: line + "\n", attributes: a))
            } else if line.hasPrefix("```") {
                var a = base; a[.foregroundColor] = Colors.comment
                result.append(NSAttributedString(string: line + "\n", attributes: a))
            } else if line.hasPrefix("> ") {
                var a = base; a[.foregroundColor] = Colors.comment
                result.append(NSAttributedString(string: line + "\n", attributes: a))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.first?.isNumber == true {
                var a = base; a[.foregroundColor] = Colors.operator_
                result.append(NSAttributedString(string: String(line.prefix(2)), attributes: a))
                result.append(NSAttributedString(string: String(line.dropFirst(2)) + "\n", attributes: base))
            } else {
                result.append(NSAttributedString(string: line + "\n", attributes: base))
            }
        }
        return result
    }

    // MARK: - Plain

    static func plain(_ source: String) -> NSAttributedString {
        NSAttributedString(
            string: source,
            attributes: [.font: monoFont, .foregroundColor: NSColor.labelColor]
        )
    }

    // MARK: - Tokenizer

    struct Token {
        enum Kind { case keyword, string, comment, number, type_, function_, operator_, plain }
        let kind: Kind
        let text: String
    }

    private static func keywords(for lang: Language) -> Set<String> {
        switch lang {
        case .swift:
            return ["func","var","let","class","struct","enum","protocol","extension",
                    "import","return","if","else","guard","switch","case","default","for",
                    "while","do","try","catch","throw","throws","in","where","init","deinit",
                    "self","super","static","final","override","public","private","internal",
                    "fileprivate","open","mutating","lazy","weak","unowned","nil","true","false",
                    "async","await","actor","nonisolated","some","any","typealias"]
        case .python:
            return ["def","class","import","from","return","if","elif","else","for","while",
                    "with","as","try","except","finally","raise","pass","break","continue",
                    "lambda","yield","and","or","not","in","is","None","True","False",
                    "async","await","global","nonlocal","del","assert"]
        case .javascript, .typescript:
            return ["const","let","var","function","class","import","export","default","return",
                    "if","else","for","while","do","switch","case","break","continue","try",
                    "catch","finally","throw","new","delete","typeof","instanceof","in","of",
                    "this","super","null","undefined","true","false","async","await","yield",
                    "from","extends","implements","interface","type","enum","abstract","static",
                    "public","private","protected","readonly","declare","namespace","module"]
        case .rust:
            return ["fn","let","mut","const","struct","enum","impl","trait","use","mod","pub",
                    "priv","crate","super","self","Self","return","if","else","match","for",
                    "while","loop","break","continue","in","where","type","unsafe","extern",
                    "async","await","move","dyn","ref","true","false","None","Some","Ok","Err"]
        case .go:
            return ["func","var","const","type","struct","interface","package","import","return",
                    "if","else","for","range","switch","case","default","select","go","defer",
                    "chan","map","slice","make","new","nil","true","false","iota","break","continue",
                    "goto","fallthrough","error"]
        case .java, .kotlin:
            return ["class","interface","enum","abstract","extends","implements","import","package",
                    "public","private","protected","static","final","void","return","if","else",
                    "for","while","do","switch","case","default","try","catch","finally","throw",
                    "throws","new","this","super","null","true","false","int","long","double",
                    "float","boolean","char","byte","short","String","fun","val","var","when",
                    "object","companion","data","sealed","override","open","lateinit","by","init"]
        case .c, .cpp:
            return ["int","long","short","char","float","double","void","bool","unsigned","signed",
                    "const","static","extern","register","volatile","auto","inline","struct","union",
                    "enum","typedef","return","if","else","for","while","do","switch","case","default",
                    "break","continue","goto","sizeof","nullptr","NULL","true","false","class",
                    "public","private","protected","virtual","override","template","typename","namespace"]
        case .shell:
            return ["if","then","else","elif","fi","for","do","done","while","until","case","esac",
                    "function","return","exit","echo","export","source","local","readonly",
                    "declare","unset","shift","break","continue","in","select"]
        default:
            return []
        }
    }

    private static func tokenize(_ source: String, language: Language) -> [Token] {
        var tokens: [Token] = []
        var chars = Array(source)
        var i = 0
        let kws = keywords(for: language)

        while i < chars.count {
            let c = chars[i]

            // Line comment: // or #
            if (c == "/" && i+1 < chars.count && chars[i+1] == "/")
                || (c == "#" && language == .python || c == "#" && language == .shell) {
                var comment = ""
                while i < chars.count && chars[i] != "\n" {
                    comment.append(chars[i]); i += 1
                }
                tokens.append(Token(kind: .comment, text: comment))
                continue
            }

            // Block comment: /* */
            if c == "/" && i+1 < chars.count && chars[i+1] == "*" {
                var comment = "/*"; i += 2
                while i < chars.count {
                    if chars[i] == "*" && i+1 < chars.count && chars[i+1] == "/" {
                        comment += "*/"; i += 2; break
                    }
                    comment.append(chars[i]); i += 1
                }
                tokens.append(Token(kind: .comment, text: comment))
                continue
            }

            // String: " or '
            if c == "\"" || c == "'" {
                let delim = c
                var str = String(c); i += 1
                while i < chars.count {
                    let sc = chars[i]
                    str.append(sc); i += 1
                    if sc == "\\" && i < chars.count { str.append(chars[i]); i += 1; continue }
                    if sc == delim { break }
                    if sc == "\n" { break }
                }
                tokens.append(Token(kind: .string, text: str))
                continue
            }

            // Number
            if c.isNumber || (c == "-" && i+1 < chars.count && chars[i+1].isNumber) {
                var num = String(c); i += 1
                while i < chars.count && (chars[i].isNumber || chars[i] == "." || chars[i] == "_" || chars[i] == "x" || chars[i] == "b") {
                    num.append(chars[i]); i += 1
                }
                tokens.append(Token(kind: .number, text: num))
                continue
            }

            // Identifier / keyword
            if c.isLetter || c == "_" {
                var word = String(c); i += 1
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    word.append(chars[i]); i += 1
                }
                // Type heuristic: starts with uppercase
                if kws.contains(word) {
                    tokens.append(Token(kind: .keyword, text: word))
                } else if word.first?.isUppercase == true {
                    tokens.append(Token(kind: .type_, text: word))
                } else if i < chars.count && chars[i] == "(" {
                    tokens.append(Token(kind: .function_, text: word))
                } else {
                    tokens.append(Token(kind: .plain, text: word))
                }
                continue
            }

            // Operators
            let opChars: Set<Character> = ["=","+","-","*","/","%","<",">","!","&","|","^","~","?",":"]
            if opChars.contains(c) {
                var op = String(c); i += 1
                while i < chars.count && opChars.contains(chars[i]) {
                    op.append(chars[i]); i += 1
                }
                tokens.append(Token(kind: .operator_, text: op))
                continue
            }

            // Everything else (whitespace, punctuation)
            tokens.append(Token(kind: .plain, text: String(c)))
            i += 1
        }

        return tokens
    }
}

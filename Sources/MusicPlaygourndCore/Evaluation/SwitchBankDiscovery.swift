import Foundation

/// Compiler-backed switch metadata used to generate the retained variant factory.
struct SwitchBankDiscovery {
    struct Control: Sendable {
        let propertyUSR: String
        let propertyName: String
        let cases: [String]
        let sites: [Site]
    }

    struct Site: Sendable {
        let switchLine: Int
        let endLine: Int
        /// Ranges are ordered to match the control's cases, rather than the source case order.
        let caseRanges: [NSRange]
    }

    struct Result: Sendable {
        let controls: [Control]
        let issues: [String]

        var isSupported: Bool { !controls.isEmpty }
    }

    private struct StoredProperty {
        let usr: String
        let name: String
        let interfaceType: String
        let isStored: Bool
        let isWritable: Bool
        let isSwiftMusicState: Bool
    }

    private static let swiftMusicStateWrapperType = "$s10SwiftMusic5StateCD"
    private static let swiftMusicStateBackingPrefix = "$s10SwiftMusic5StateCy"
    private static let performanceEntryProtocol = "s:10SwiftMusic16PerformanceEntryP"

    private struct EnumDefinition {
        let usr: String
        let cases: [String]
        let simple: Bool
    }

    private struct RawSite {
        let propertyUSR: String
        let propertyName: String
        let enumType: String
        let switchStart: Int
        let switchEnd: Int
        let cases: [(name: String, start: Int, end: Int)]
    }

    static func discover(ast: Data, source: String, prefixBytes: Int, entryType: String = "Session") throws -> Result {
        guard let root = try JSONSerialization.jsonObject(with: ast) as? [String: Any],
              root["_kind"] as? String == "source_file" else {
            throw EvaluationError.invalidResult("Unsupported Swift AST format for switch discovery.")
        }

        if sessionConformsToPerformanceEntry(root, entryType: entryType) {
            return Result(
                controls: [],
                issues: ["Swift switch banks are unavailable for PerformanceEntry sessions."]
            )
        }

        let enums = collectEnums(root)
        let properties = collectSessionProperties(root, entryType: entryType)
        var rawSites = [RawSite]()
        var issues = [String]()
        var seenSites = Set<String>()
        collectSwitches(
            root,
            properties: properties,
            enums: enums,
            prefixBytes: prefixBytes,
            source: source,
            rawSites: &rawSites,
            issues: &issues,
            seenSites: &seenSites
        )

        var grouped = [String: [RawSite]]()
        for site in rawSites {
            grouped[site.propertyUSR, default: []].append(site)
        }

        var controls = [Control]()
        for propertyUSR in grouped.keys.sorted() {
            guard let sites = grouped[propertyUSR], let first = sites.first else { continue }
            let controlCases = first.cases.map { $0.name }
            guard controlCases.count >= 2 else { continue }
            var normalizedSites = [Site]()
            var supported = true
            for site in sites {
                guard Set(site.cases.map { $0.name }) == Set(controlCases),
                      site.cases.count == controlCases.count,
                      Set(site.cases.map { $0.name }).count == site.cases.count else {
                    issues.append("Switch sites for \(first.propertyName) do not have the same exhaustive cases.")
                    supported = false
                    break
                }
                var ranges = [NSRange]()
                for name in controlCases {
                    guard let value = site.cases.first(where: { $0.name == name }) else {
                        supported = false
                        break
                    }
                    ranges.append(try utf16Range(start: value.start, end: value.end, source: source, prefixBytes: prefixBytes))
                }
                guard supported else { break }
                let line = lineNumber(at: site.switchStart, source: source, prefixBytes: prefixBytes)
                let endLine = lineNumber(at: max(site.switchStart, site.switchEnd - 1), source: source, prefixBytes: prefixBytes)
                normalizedSites.append(Site(switchLine: line, endLine: endLine, caseRanges: ranges))
            }
            guard supported, let property = properties[propertyUSR] else { continue }
            controls.append(Control(
                propertyUSR: propertyUSR,
                propertyName: property.name,
                cases: controlCases,
                sites: normalizedSites
            ))
        }
        controls.sort { $0.propertyName < $1.propertyName }
        var expectedVariants = 1
        for control in controls {
            guard control.cases.count > 0,
                  expectedVariants <= PreparedSwitchBank.maximumVariants / control.cases.count else {
                issues.append("Swift switch bank exceeds the 16-variant bound.")
                return Result(controls: [], issues: Array(Set(issues)).sorted())
            }
            expectedVariants *= control.cases.count
        }
        guard controls.count <= 16 else {
            issues.append("Swift switch bank exceeds the 16-control bound.")
            return Result(controls: [], issues: Array(Set(issues)).sorted())
        }
        return Result(controls: controls, issues: Array(Set(issues)).sorted())
    }

    private static func sessionConformsToPerformanceEntry(_ root: [String: Any], entryType: String) -> Bool {
        var result = false
        walk(root) { object in
            guard !result,
                  object["_kind"] as? String == "struct_decl",
                  baseName(object["name"]) == entryType,
                  let inheritance = object["inherits"] as? [String: Any],
                  let conformances = inheritance["conformances"] as? [Any] else { return }
            result = conformances.contains { value in
                guard let conformance = value as? [String: Any] else { return false }
                if conformance["protocol"] as? String == performanceEntryProtocol { return true }
                if let protocolName = baseName(conformance["protocol"]) {
                    return protocolName == "PerformanceEntry"
                }
                return false
            }
        }
        return result
    }

    private static func collectEnums(_ root: [String: Any]) -> [String: EnumDefinition] {
        var result = [String: EnumDefinition]()
        walk(root) { object in
            guard object["_kind"] as? String == "enum_decl",
                  object["implicit"] as? Bool != true,
                  let usr = object["usr"] as? String,
                  let members = object["members"] as? [Any] else { return }
            var names = [String]()
            var simple = true
            for member in members {
                guard let item = member as? [String: Any] else { continue }
                if item["_kind"] as? String == "enum_element_decl" {
                    guard let name = baseName(item["name"]) else { simple = false; continue }
                    if item["params"] != nil || item["parameter_clause"] != nil || item["associated_values"] != nil {
                        simple = false
                    }
                    names.append(name)
                }
            }
            var unique = [String]()
            for name in names where !unique.contains(name) { unique.append(name) }
            guard unique.count >= 2 else { return }
            result[usr] = EnumDefinition(usr: usr, cases: unique, simple: simple && unique.count == names.count)
        }
        return result
    }

    private static func collectSessionProperties(_ root: [String: Any], entryType: String) -> [String: StoredProperty] {
        struct Declaration {
            let usr: String
            let name: String
            let interfaceType: String
            let isImplicit: Bool
            let isStored: Bool
            let isWritable: Bool
            let hasSwiftMusicStateAttribute: Bool
        }
        var declarations = [Declaration]()
        walk(root, context: nil) { object, context in
            guard context == entryType,
                  object["_kind"] as? String == "var_decl",
                  let usr = object["usr"] as? String,
                  let name = baseName(object["name"]),
                  let interfaceType = object["interface_type"] as? String else { return }
            let attrs = object["attrs"] as? [[String: Any]] ?? []
            let hasSwiftMusicStateAttribute = attrs.contains { attribute in
                attribute["_kind"] as? String == "custom_attr"
                    && attribute["type"] as? String == swiftMusicStateWrapperType
            }
            declarations.append(Declaration(
                usr: usr,
                name: name,
                interfaceType: interfaceType,
                isImplicit: object["implicit"] as? Bool == true,
                isStored: object["readImpl"] as? String == "stored",
                isWritable: object["writeImpl"] as? String == "stored",
                hasSwiftMusicStateAttribute: hasSwiftMusicStateAttribute
            ))
        }
        let backings = Set(declarations.compactMap { declaration -> String? in
            guard declaration.isImplicit,
                  declaration.name.hasPrefix("_"),
                  declaration.isStored,
                  declaration.isWritable,
                  declaration.interfaceType.hasPrefix(swiftMusicStateBackingPrefix) else { return nil }
            return declaration.name
        })
        var result = [String: StoredProperty]()
        for declaration in declarations where !declaration.isImplicit && !declaration.name.hasPrefix("$") {
            let stateBacking = "_" + declaration.name
            let isStateBacked = declaration.hasSwiftMusicStateAttribute && backings.contains(stateBacking)
            result[declaration.usr] = StoredProperty(
                usr: declaration.usr,
                name: declaration.name,
                interfaceType: declaration.interfaceType,
                isStored: declaration.isStored || isStateBacked,
                isWritable: declaration.isWritable || isStateBacked,
                isSwiftMusicState: isStateBacked
            )
        }
        return result
    }

    private static func collectSwitches(
        _ root: [String: Any],
        properties: [String: StoredProperty],
        enums: [String: EnumDefinition],
        prefixBytes: Int,
        source: String,
        rawSites: inout [RawSite],
        issues: inout [String],
        seenSites: inout Set<String>
    ) {
        walk(root) { object in
            guard object["_kind"] as? String == "switch_stmt",
                  object["implicit"] as? Bool != true,
                  let range = sourceRange(object["range"]),
                  let subjectExpr = object["subject_expr"] as? [String: Any] else { return }
            guard let subject = stateSubject(subjectExpr) else {
                issues.append("Swift switch at byte \(range.start) is unavailable because its discriminant is not a Session property.")
                return
            }
            guard let declaration = subject["decl"] as? [String: Any],
                  let propertyUSR = declaration["decl_usr"] as? String else {
                issues.append("Swift switch at byte \(range.start) is unavailable because its discriminant declaration is unresolved.")
                return
            }
            let propertyName = baseName(declaration["base_name"]) ?? "unknown"
            guard let property = properties[propertyUSR] else {
                issues.append("Switch for \(propertyName) is unavailable because its discriminant is not a Session SwiftMusic.State property.")
                return
            }
            guard let type = subject["type"] as? String,
                  let enumDefinition = matchingEnum(type: type, enums: enums) else {
                issues.append("Switch for \(property.name) is unavailable because its enum type is unresolved.")
                return
            }

            guard property.isSwiftMusicState else {
                issues.append("Switch for \(property.name) is unavailable because its Session property is not backed by SwiftMusic.State.")
                return
            }
            guard enumDefinition.simple else {
                issues.append("Switch for \(property.name) is unavailable because its State property is not a writable plain enum.")
                return
            }

            guard let cases = object["cases"] as? [Any], cases.count == enumDefinition.cases.count else {
                issues.append("Switch for \(property.name) is unavailable because it is not an exhaustive simple enum switch.")
                return
            }
            var labels = [(name: String, start: Int, end: Int)]()
            for value in cases {
                guard let caseObject = value as? [String: Any],
                      caseObject["_kind"] as? String == "case_stmt",
                      let caseRange = sourceRange(caseObject["range"]),
                      let items = caseObject["case_label_items"] as? [Any], items.count == 1,
                      let item = items.first as? [String: Any],
                      let pattern = item["pattern"] as? [String: Any],
                      pattern["_kind"] as? String == "pattern_enum_element",
                      let name = baseName(pattern["element"]),
                      enumDefinition.cases.contains(name) else {
                    issues.append("Switch for \(property.name) contains an unsupported case pattern.")
                    return
                }
                labels.append((name: name, start: caseRange.start, end: caseRange.end))
            }
            guard Set(labels.map { $0.name }).count == labels.count,
                  Set(labels.map { $0.name }) == Set(enumDefinition.cases) else {
                issues.append("Switch for \(property.name) does not cover each enum case exactly once.")
                return
            }
            let key = "\(propertyUSR):\(range.start):\(range.end)"
            guard seenSites.insert(key).inserted else { return }
            rawSites.append(RawSite(
                propertyUSR: propertyUSR,
                propertyName: property.name,
                enumType: type,
                switchStart: range.start,
                switchEnd: range.end,
                cases: labels
            ))
        }
    }

    private static func stateSubject(_ expression: [String: Any]) -> [String: Any]? {
        if expression["_kind"] as? String == "member_ref_expr" { return expression }
        if expression["_kind"] as? String == "load_expr",
           expression["implicit"] as? Bool == true,
           let subject = expression["sub_expr"] as? [String: Any],
           subject["_kind"] as? String == "member_ref_expr" { return subject }
        return nil
    }

    private static func matchingEnum(type: String, enums: [String: EnumDefinition]) -> EnumDefinition? {
        enums.values.first { definition in
            let normalized = "$" + definition.usr.replacingOccurrences(of: ":", with: "")
            return type == normalized || type.hasPrefix(normalized)
        }
    }

    private static func sourceRange(_ value: Any?) -> (start: Int, end: Int)? {
        guard let range = value as? [String: Any],
              let start = range["start"] as? Int,
              let end = range["end"] as? Int,
              start >= 0, end >= start else { return nil }
        return (start, end)
    }

    private static func baseName(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let object = value as? [String: Any] else { return nil }
        if let name = object["name"] as? String { return name }
        return baseName(object["base_name"])
    }

    private static func utf16Range(start: Int, end: Int, source: String, prefixBytes: Int) throws -> NSRange {
        let lower = start - prefixBytes
        let upper = end - prefixBytes
        let bytes = Array(source.utf8)
        guard lower >= 0, upper >= lower, upper <= bytes.count else {
            throw EvaluationError.invalidResult("Swift switch source range is outside Session.swift.")
        }
        let startString = String(decoding: bytes[..<lower], as: UTF8.self)
        let endString = String(decoding: bytes[..<upper], as: UTF8.self)
        let location = startString.utf16.count
        let length = max(1, endString.utf16.count - location)
        return NSRange(location: location, length: length)
    }

    private static func lineNumber(at byteOffset: Int, source: String, prefixBytes: Int) -> Int {
        let offset = max(0, min(source.utf8.count, byteOffset - prefixBytes))
        return source.utf8.prefix(offset).reduce(into: 1) { count, byte in
            if byte == 10 { count += 1 }
        }
    }

    private static func walk(_ value: Any, context: String? = nil, _ body: ([String: Any]) -> Void) {
        if let object = value as? [String: Any] {
            body(object)
            let nextContext: String?
            if object["_kind"] as? String == "struct_decl" {
                nextContext = baseName(object["name"])
            } else {
                nextContext = context
            }
            for child in object.values { walk(child, context: nextContext, body) }
        } else if let array = value as? [Any] {
            for child in array { walk(child, context: context, body) }
        }
    }

    private static func walk(_ value: Any, _ body: ([String: Any]) -> Void) {
        walk(value, context: nil, body)
    }

    private static func walk(
        _ value: Any,
        context: String?,
        _ body: ([String: Any], String?) -> Void
    ) {
        if let object = value as? [String: Any] {
            body(object, context)
            let nextContext: String?
            if object["_kind"] as? String == "struct_decl" {
                nextContext = baseName(object["name"])
            } else {
                nextContext = context
            }
            for child in object.values { walk(child, context: nextContext, body) }
        } else if let array = value as? [Any] {
            for child in array { walk(child, context: context, body) }
        }
    }
}

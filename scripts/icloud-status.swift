import Foundation
import CryptoKit
// Read-only, explicit target files only; no account changes or service restarts.
let keys: Set<URLResourceKey> = [.isRegularFileKey,.isUbiquitousItemKey,.ubiquitousItemIsUploadedKey,.ubiquitousItemIsUploadingKey,.ubiquitousItemUploadingErrorKey,.ubiquitousItemHasUnresolvedConflictsKey]
var rows: [[String:Any]] = []
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath:path)
    var row: [String:Any] = ["path":path,"checkedAt":ISO8601DateFormatter().string(from:Date())]
    do {
        let values = try url.resourceValues(forKeys:keys)
        row["ubiquitous"] = values.isUbiquitousItem ?? false
        row["uploaded"] = values.ubiquitousItemIsUploaded ?? false
        row["uploading"] = values.ubiquitousItemIsUploading ?? false
        row["conflicts"] = values.ubiquitousItemHasUnresolvedConflicts ?? false
        if let error = values.ubiquitousItemUploadingError as NSError? { row["errorDomain"] = error.domain; row["errorCode"] = error.code }
        if values.isRegularFile == true { row["sha256"] = SHA256.hash(data:try Data(contentsOf:url)).map {String(format:"%02x",$0)}.joined() }
    } catch { row["probeError"] = error.localizedDescription }
    rows.append(row)
}
let data = try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys])
print(String(decoding:data,as:UTF8.self))

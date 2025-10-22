function redact_signature(tag, timestamp, record, flb)
    local message = record["log"]
    if message then
        -- Refined regex: match "Signature=" followed by base64url characters (word chars, hyphen, and equals sign)
        message = string.gsub(message, "(Signature=)([%w%-=]+)", "%1******")
        record["log"] = message
    end
    return 1, timestamp, record
end
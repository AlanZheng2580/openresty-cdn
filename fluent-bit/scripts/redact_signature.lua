function redact_signature(tag, timestamp, record, flb)
    local message = record["message"]
    if message then
        -- Refined regex: match "Signature=" followed by base64url characters (word chars, hyphen, and equals sign)
        message = string.gsub(message, "(Signature=)([%w%-=]+)", "%1******")
        record["message"] = message
    end
    return 2, timestamp, record
end
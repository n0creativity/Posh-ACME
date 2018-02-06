function ConvertFrom-Jwk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,Position=0,ValueFromPipeline)]
        [string]$JWK
    )

    # RFC 7515 - JSON Web Key (JWK)
    # https://tools.ietf.org/html/rfc7517

    # Support enough of a subset of RFC 7515 to implement the ACME v2
    # protocol.
    # https://tools.ietf.org/html/draft-ietf-acme-acme-09

    # This basically includes RSA keys 2048-4096 bits and EC keys utilizing
    # P-256, P-384, or P-521 curves.

    Process {

        try {
            $jwkObject = $JWK | ConvertFrom-Json
        } catch { throw }

        if ('kty' -notin $jwkObject.PSObject.Properties.Name) {
            throw "Invalid JWK. No 'kty' element found."
        }

        # create a KeyParameters object from the values given for each key type
        switch ($jwkObject.kty) {

            'RSA' {
                $keyParams = New-Object Security.Cryptography.RSAParameters

                # make sure we have the required public key parameters per
                # https://tools.ietf.org/html/rfc7518#section-6.3.1
                $hasE = ![string]::IsNullOrWhiteSpace($jwkObject.e)
                $hasN = ![string]::IsNullOrWhiteSpace($jwkObject.n)
                if ($hasE -and $hasN) {
                    $keyParams.Exponent = $jwkObject.e  | ConvertFrom-Base64Url -AsByteArray
                    $keyParams.Modulus  = $jwkObject.n  | ConvertFrom-Base64Url -AsByteArray
                } else {
                    throw "Invalid RSA JWK. Missing one or more public key parameters."
                }

                # Add the private key parameters if they were included
                # Per https://tools.ietf.org/html/rfc7518#section-6.3.2, 
                # 'd' is the only required private parameter. The rest SHOULD
                # be included and if any *are* included then they all MUST be included.
                if (![string]::IsNullOrWhiteSpace($jwkObject.d)) {
                    $keyParams.D = $jwkObject.d | ConvertFrom-Base64Url -AsByteArray

                    # check for the rest
                    $hasP = ![string]::IsNullOrWhiteSpace($jwkObject.P)
                    $hasQ = ![string]::IsNullOrWhiteSpace($jwkObject.Q)
                    $hasDP = ![string]::IsNullOrWhiteSpace($jwkObject.DP)
                    $hasDQ = ![string]::IsNullOrWhiteSpace($jwkObject.DQ)
                    $hasQI = ![string]::IsNullOrWhiteSpace($jwkObject.QI)

                    if ($hasP -and $hasQ -and $hasDP -and $hasDQ -and $hasQI) {
                        $keyParams.P        = $jwkObject.p  | ConvertFrom-Base64Url -AsByteArray
                        $keyParams.Q        = $jwkObject.q  | ConvertFrom-Base64Url -AsByteArray
                        $keyParams.DP       = $jwkObject.dp | ConvertFrom-Base64Url -AsByteArray
                        $keyParams.DQ       = $jwkObject.dq | ConvertFrom-Base64Url -AsByteArray
                        $keyParams.InverseQ = $jwkObject.qi | ConvertFrom-Base64Url -AsByteArray
                    } elseif ($hasP -or $hasQ -or $hasDP -or $hasDQ -or $hasQI) {
                        throw "Invalid RSA JWK. Incomplete set of private key parameters."
                    }
                }

                # create the key
                $key = New-Object Security.Cryptography.RSACryptoServiceProvider
                $key.ImportParameters($keyParams)
                break;
            }

            'EC' {
                # check for a valid curve
                if ('crv' -notin $jwkObject.PSObject.Properties.Name) {
                    throw "Invalid JWK. No 'crv' found for key type EC."
                }
                switch ($jwkObject.crv) {
                    'P-256' {
                        # nistP256 / secP256r1 / x962P256v1
                        $Curve = [Security.Cryptography.ECCurve]::CreateFromValue('1.2.840.10045.3.1.7')
                        break;
                    }
                    'P-384' {
                        # secP384r1
                        $Curve = [Security.Cryptography.ECCurve]::CreateFromValue('1.3.132.0.34')
                        break;
                    }
                    'P-521' {
                        $Curve = [Security.Cryptography.ECCurve]::CreateFromValue('1.3.132.0.35')
                        break;
                    }
                    default {
                        throw "Unsupported JWK curve (crv) found."
                    }
                }

                # make sure we have the required public key parameters per
                # https://tools.ietf.org/html/rfc7518#section-6.2.1
                $hasX = ![string]::IsNullOrWhiteSpace($jwkObject.x)
                $hasY = ![string]::IsNullOrWhiteSpace($jwkObject.y)
                if ($hasX -and $hasY) {
                    $Q = New-Object Security.Cryptography.ECPoint
                    $Q.X = $jwkObject.x | ConvertFrom-Base64Url -AsByteArray
                    $Q.Y = $jwkObject.y | ConvertFrom-Base64Url -AsByteArray
                    $keyParams = New-Object Security.Cryptography.ECParameters
                    $keyParams.Q = $Q
                    $keyParams.Curve = $Curve
                } else {
                    throw "Invalid EC JWK. Missing one or more public key parameters."
                }

                # build the key parameters
                if (![string]::IsNullOrWhiteSpace($jwkObject.d)) {
                    $keyParams.D = $jwkObject.d | ConvertFrom-Base64Url -AsByteArray
                }

                # create the key
                $key = [Security.Cryptography.ECDsa]::Create()
                $key.ImportParameters($keyParams)
                break;
            }
            default {
                throw "Unsupported JWK key type (kty) found."
            }
        }

        # return the key
        return $key
    }
}
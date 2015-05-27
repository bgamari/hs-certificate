{-# LANGUAGE ScopedTypeVariables #-}
module Main where

import Test.Tasty
import Test.Tasty.QuickCheck

import qualified Data.ByteString as B

import Control.Applicative
import Control.Monad

import Data.List (nub, sort)
import Data.ASN1.Types
import Data.X509
import qualified Crypto.Types.PubKey.RSA as RSA
import qualified Crypto.Types.PubKey.DSA as DSA

import Data.Hourglass

instance Arbitrary RSA.PublicKey where
    arbitrary = do
        bytes <- elements [64,128,256]
        e     <- elements [0x3,0x10001]
        n     <- choose (2^(8*(bytes-1)),2^(8*bytes))
        return $ RSA.PublicKey { RSA.public_size = bytes
                               , RSA.public_n    = n
                               , RSA.public_e    = e
                               }

instance Arbitrary DSA.Params where
    arbitrary = DSA.Params <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary DSA.PublicKey where
    arbitrary = DSA.PublicKey <$> arbitrary <*> arbitrary

instance Arbitrary PubKey where
    arbitrary = oneof
        [ PubKeyRSA <$> arbitrary
        , PubKeyDSA <$> arbitrary
        --, PubKeyECDSA ECDSA_Hash_SHA384 <$> (B.pack <$> replicateM 384 arbitrary)
        ]

instance Arbitrary HashALG where
    arbitrary = elements [HashMD2,HashMD5,HashSHA1,HashSHA224,HashSHA256,HashSHA384,HashSHA512]

instance Arbitrary PubKeyALG where
    arbitrary = elements [PubKeyALG_RSA,PubKeyALG_DSA,PubKeyALG_ECDSA,PubKeyALG_DH]

instance Arbitrary SignatureALG where
    -- unfortunately as the encoding of this is a single OID as opposed to two OID,
    -- the testing need to limit itself to Signature ALG that has been defined in the OID database. 
    -- arbitrary = SignatureALG <$> arbitrary <*> arbitrary
    arbitrary = elements
        [ SignatureALG HashSHA1 PubKeyALG_RSA
        , SignatureALG HashMD5 PubKeyALG_RSA
        , SignatureALG HashMD2 PubKeyALG_RSA
        , SignatureALG HashSHA256 PubKeyALG_RSA
        , SignatureALG HashSHA384 PubKeyALG_RSA
        , SignatureALG HashSHA512 PubKeyALG_RSA
        , SignatureALG HashSHA224 PubKeyALG_RSA
        , SignatureALG HashSHA1 PubKeyALG_DSA
        , SignatureALG HashSHA224 PubKeyALG_ECDSA
        , SignatureALG HashSHA256 PubKeyALG_ECDSA
        , SignatureALG HashSHA384 PubKeyALG_ECDSA
        , SignatureALG HashSHA512 PubKeyALG_ECDSA
        ]

arbitraryBS r1 r2 = choose (r1,r2) >>= \l -> (B.pack <$> replicateM l arbitrary)

instance Arbitrary ASN1StringEncoding where
    arbitrary = elements [IA5,UTF8]

instance Arbitrary ASN1CharacterString where
    arbitrary = ASN1CharacterString <$> arbitrary <*> arbitraryBS 2 36

instance Arbitrary DistinguishedName where
    arbitrary = DistinguishedName <$> (choose (1,5) >>= \l -> replicateM l arbitraryDE)
      where arbitraryDE = (,) <$> arbitrary <*> arbitrary

instance Arbitrary DateTime where
    arbitrary = timeConvert <$> (arbitrary :: Gen Elapsed)
instance Arbitrary Elapsed where
    arbitrary = Elapsed . Seconds <$> (choose (1, 100000000))

instance Arbitrary Extensions where
    arbitrary = Extensions <$> oneof
        [ pure Nothing
        , Just <$> (listOf1 $ oneof
            [ extensionEncode <$> arbitrary <*> (arbitrary :: Gen ExtKeyUsage)
            ]
            )
        ]

instance Arbitrary ExtKeyUsageFlag where
    arbitrary = elements $ enumFrom KeyUsage_digitalSignature
instance Arbitrary ExtKeyUsage where
    arbitrary = ExtKeyUsage . sort . nub <$> listOf1 arbitrary

instance Arbitrary ExtKeyUsagePurpose where
    arbitrary = elements [ KeyUsagePurpose_ServerAuth
                         , KeyUsagePurpose_ClientAuth
                         , KeyUsagePurpose_CodeSigning
                         , KeyUsagePurpose_EmailProtection
                         , KeyUsagePurpose_TimeStamping
                         , KeyUsagePurpose_OCSPSigning ]
instance Arbitrary ExtExtendedKeyUsage where
    arbitrary = ExtExtendedKeyUsage . nub <$> listOf1 arbitrary

instance Arbitrary Certificate where
    arbitrary = Certificate <$> pure 2
                            <*> arbitrary
                            <*> arbitrary
                            <*> arbitrary
                            <*> arbitrary
                            <*> arbitrary
                            <*> arbitrary
                            <*> arbitrary

instance Arbitrary RevokedCertificate where
    arbitrary = RevokedCertificate <$> arbitrary
                                   <*> arbitrary
                                   <*> pure (Extensions Nothing)

instance Arbitrary CRL where
    arbitrary = CRL <$> pure 1
                    <*> arbitrary
                    <*> arbitrary
                    <*> arbitrary
                    <*> arbitrary
                    <*> arbitrary
                    <*> arbitrary

property_unmarshall_marshall_id :: (Show o, Arbitrary o, ASN1Object o, Eq o) => o -> Bool
property_unmarshall_marshall_id o =
    case got of
        Right (gotObject, [])
            | gotObject == o -> True
            | otherwise      -> error ("object is different: " ++ show gotObject ++ " expecting " ++ show o)
        Right (gotObject, l) -> error ("state remaining: " ++ show l ++ " marshalled: " ++ show oMarshalled ++ " parsed: " ++ show gotObject)
        Left e               -> error ("parsing failed: " ++ show e ++ " object: " ++ show o ++ " marshalled as: " ++ show oMarshalled)
  where got = fromASN1 oMarshalled
        oMarshalled = toASN1 o []

property_extension_id :: (Show e, Eq e, Extension e) => e -> Bool
property_extension_id e = case extDecode (extEncode e) of
                                Left err -> error err
                                Right v | v == e    -> True
                                        | otherwise -> error ("expected " ++ show e ++ " got: " ++ show v)

main = defaultMain $ testGroup "X509"
    [ testGroup "marshall"
        [ testProperty "pubkey" (property_unmarshall_marshall_id :: PubKey -> Bool)
        , testProperty "signature alg" (property_unmarshall_marshall_id :: SignatureALG -> Bool)
        , testGroup "extension"
            [ testProperty "key-usage" (property_extension_id :: ExtKeyUsage -> Bool)
            , testProperty "extended-key-usage" (property_extension_id :: ExtExtendedKeyUsage -> Bool)
            ]
        , testProperty "extensions" (property_unmarshall_marshall_id :: Extensions -> Bool)
        , testProperty "certificate" (property_unmarshall_marshall_id :: Certificate -> Bool)
        , testProperty "crl" (property_unmarshall_marshall_id :: CRL -> Bool)
        ]
    ]

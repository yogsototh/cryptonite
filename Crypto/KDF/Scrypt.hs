-- |
-- Module      : Crypto.KDF.Scrypt
-- License     : BSD-style
-- Maintainer  : Vincent Hanquez <vincent@snarc.org>
-- Stability   : experimental
-- Portability : unknown
--
-- Scrypt key derivation function as defined in Colin Percival's paper "Stronger Key Derivation via Sequential Memory-Hard Functions" <http://www.tarsnap.com/scrypt/scrypt.pdf>.
--
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE CPP #-}
module Crypto.KDF.Scrypt
    ( Parameters(..)
    , generate
    ) where

import           Data.Word
import           Data.ByteString (ByteString)
import           Foreign.Marshal.Alloc
import           Foreign.Ptr (Ptr, plusPtr)
import           Control.Monad (forM_)

import           Crypto.Hash (SHA256(..))
import qualified Crypto.KDF.PBKDF2 as PBKDF2
import           Crypto.Internal.Compat (popCount, unsafeDoIO)
import qualified Crypto.Internal.ByteArray as B
import           Crypto.Internal.Bytes (bufCopy)

-- | Parameters for Scrypt
data Parameters = Parameters
    { password     :: ByteString -- ^ Password (bytes encoded)
    , salt         :: ByteString -- ^ Salt (bytes encoded)
    , n            :: Word64     -- ^ Cpu/Memory cost ratio. must be a power of 2 greater than 1. also known as N.
    , r            :: Int        -- ^ Must satisfy r * p < 2^30
    , p            :: Int        -- ^ Must satisfy r * p < 2^30
    , outputLength :: Int        -- ^ the number of bytes to generate out of Scrypt
    }

foreign import ccall "cryptonite_scrypt_smix"
    ccryptonite_scrypt_smix :: Ptr Word8 -> Word32 -> Word64 -> Ptr Word8 -> Ptr Word8 -> IO ()

-- | Generate the scrypt key derivation data
generate :: Parameters -> ByteString
generate params
    | r params * p params >= 0x40000000 =
        error "Scrypt: invalid parameters: r and p constraint"
    | popCount (n params) /= 1 =
        error "Scrypt: invalid parameters: n not a power of 2"
    | otherwise = unsafeDoIO $ do
        let b = PBKDF2.generate prf (PBKDF2.Parameters (password params) (salt params) 1 intLen) :: B.Bytes
        newSalt <- B.copy b $ \bPtr ->
            allocaBytesAligned (128*(fromIntegral $ n params)*(r params)) 8 $ \v ->
            allocaBytesAligned (256*r params) 8 $ \xy -> do
                forM_ [0..(p params-1)] $ \i ->
                    ccryptonite_scrypt_smix (bPtr `plusPtr` (i * 128 * (r params)))
                                            (fromIntegral $ r params) (n params) v xy

        return $ PBKDF2.generate prf (PBKDF2.Parameters (password params) newSalt 1 (outputLength params))
  where prf    = PBKDF2.prfHMAC SHA256
        intLen = p params * 128 * r params
{-# NOINLINE generate #-}

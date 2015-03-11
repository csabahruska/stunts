{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE TemplateHaskell #-}
module MachineState where

import Data.Word
import Data.Bits
import Control.Concurrent.MVar
import qualified Data.Vector as V
import qualified Data.IntMap.Strict as IM
import qualified Data.ByteString as BS
import qualified Data.Vector.Storable.Mutable as U
import Control.Monad.State
import Control.Monad.Except
import Control.Lens as Lens

--import Edsl

data Halt
    = CleanHalt
    | Interr
    | Err String
  deriving Show

data Request
    = AskInterrupt Word8
    | PrintFreqTable (MVar ())

type Flags = Word16

wordToFlags :: Word16 -> Flags
wordToFlags w = fromIntegral $ (w .&. 0xed3) .|. 0x2

type Region = (Int, Int)
type MemPiece = ([Region], Int)

data Config_ = Config_
    { _verboseLevel     :: Int
    , _instPerSec       :: Int
    , _stepsCounter     :: Int
    , _counter          :: Maybe Int -- counter to count down
    , _speaker          :: Word8     -- 0x61 port
    , _palette          :: MVar (V.Vector Word32)
    , _keyDown          :: MVar Word16
    , _interruptRequest :: MVar (Maybe Request)
    }

$(makeLenses ''Config_)

defConfig = Config_
    { _verboseLevel = 2
    , _instPerSec   = 3 * 71000 -- 710000
    , _stepsCounter = 0
    , _counter = Nothing
    , _speaker = 0x30 -- ??
    , _palette = undefined
    , _keyDown = undefined
    , _interruptRequest = undefined
    }

data Regs = Regs { _ax_,_dx_,_bx_,_cx_, _si_,_di_, _cs_,_ss_,_ds_,_es_, _ip_,_sp_,_bp_ :: Word16 }

$(makeLenses ''Regs)

type UVec = U.IOVector Word16
type Cache1 = IM.IntMap (Int, Int, Machine ())
type Cache = (Cache1, IM.IntMap Int)

data MachineState = MachineState
    { _flags_   :: Flags
    , _regs     :: Regs
    , _heap     :: MemPiece
    , _heap''   :: UVec

    , _traceQ   :: [String]
    , _config   :: Config_
    , _cache    :: Cache
    , _labels   :: IM.IntMap BS.ByteString
    , _files    :: IM.IntMap (FilePath, BS.ByteString, Int)  -- filename, file, position
    , _dta      :: Int
    , _retrace  :: [Word16]
    , _intMask  :: Word8
    }

emptyState heap = MachineState
    { _flags_   = wordToFlags 0xf202
    , _regs     = Regs 0 0 0 0  0 0  0 0 0 0  0 0 0
    , _heap     = undefined
    , _heap''    = heap

    , _traceQ   = []
    , _config   = defConfig
    , _cache    = (IM.empty, IM.empty)
    , _labels   = IM.empty
    , _files    = IM.empty
    , _dta      = 0
    , _retrace  = cycle [1,9,0,8] --     [1,0,0,0,0,0,0,1,1,0,0,0,0,0,0,1,0,0,0,0,0,0]
    , _intMask  = 0xf8
    }

type Machine = ExceptT Halt (StateT MachineState IO)
type MachinePart a = Lens' MachineState a

$(makeLenses ''MachineState)


{-# LANGUAGE OverloadedStrings #-}

module Light
    where

import Prelude
import Prelude hiding (any, mapM_)
import Control.Monad hiding (mapM_)
import Data.Foldable hiding (elem)
import Data.Maybe
import Data.Word8
import System.Environment
import Data.Char as Char
import Data.List
import Data.Cross
import Foreign.C.Types
import SDL.Vect
import SDL (($=))
import qualified SDL
import SDL_Aux
import Control.Lens
import Data.List.Split
import Data.Vec

data Light = Light {direction   :: Vec3 Double}


load_light :: IO Light
load_light = return $ Light (Vec3 0 0 (-1))
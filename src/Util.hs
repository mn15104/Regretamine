{-# LANGUAGE OverloadedStrings #-}

module Util
    where


import Prelude hiding (any, mapM_)
import Control.Monad hiding (mapM_)
import Control.Arrow ((***))
import Data.Foldable hiding (elem)
import Data.Maybe
import Data.Word8
import Data.List
import Data.Cross
import Foreign.C.Types
import SDL.Vect
import SDL (($=))
import qualified SDL
import Matrix as Matrix
import qualified Data.Vector as V
import Data.Vec
import Codec.Picture
import Codec.Picture.Types

clamp :: Double -> Double -> Double -> Double
clamp x minval maxval = min (max x minval) maxval

stringListToVec3List :: [String] -> [Vec3 Double]
stringListToVec3List str = case str of (x:xs) -> let (a:b:c:_) = take 3 (str) in ((Vec3 (read a) (read b) (read c)):(stringListToVec3List $ drop 3 str))
                                     [] -> []

stringListToVec2List :: [[String]] -> [Vec2 Double]
stringListToVec2List str = [(Vec2 (read a) (read b) ) | (a:b:_) <- (str) ]

stringListToVec3ListI :: [[String]] -> [Vec3 Integer]
stringListToVec3ListI str = [(Vec3 (read a) (read b) (read c) ) | (a:b:c:_) <- (str) ]

mapTuple2 :: (a -> b) -> (a, a) -> (b, b)
mapTuple2 f (a1, a2) = (f a1, f a2)

mapTuple3 :: (a -> b) -> (a, a, a) -> (b, b, b)
mapTuple3 f (a1, a2, a3) = (f a1, f a2, f a3)

replaceAt :: a -> Int -> V.Vector a -> V.Vector a 
replaceAt newElement n array = V.take n array V.++  (newElement `V.cons` V.drop (n + 1) array)

to_double :: Int -> Double
to_double x = fromIntegral x

map2 :: (Functor f) => (a -> b) -> f (f a) -> f (f b)
map2 f fa = fmap (fmap f) fa

map3 :: (Functor f) => (a -> b) -> f (f (f a)) -> f (f (f b))
map3 f fa = fmap (fmap (fmap f)) fa


reduce_zbuffer :: [V.Vector (Double, Vec4 Word8)] ->  (V.Vector (Double, Vec4 Word8))
reduce_zbuffer zbuffers =  foldr (\veca vecb -> V.map (\((zindex1, rgba1),(zindex2, rgba2)) -> if zindex1 > zindex2 then (zindex1, rgba1) else (zindex2, rgba2)) (V.zip veca vecb) ) V.empty zbuffers
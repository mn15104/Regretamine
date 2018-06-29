{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

        -- |‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾| -- 
        -- |                                                                        | -- 
        -- |                       RASTERIZING OPERATIONS                           | -- 
        -- |                                                                        | -- 
        -- |                                                                        | -- 
        --  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾  -- 


module Rasteriser
    where

import Prelude hiding (any, mapM_)
import SDL.Vect hiding (dot, normalize)
import SDL (($=))
import qualified SDL
import Debug.Trace as Trace
import Data.Word8
import qualified Data.Vector as V
import Data.Cross
import Camera
import Model
import SDLx
import Light
import Geometry
import Util
import Shader
import Data.Vec as Vec hiding (map, foldr)
import qualified Data.Vec as Vec  (map, foldr)
import Types

load_zbuffer :: Screen -> V.Vector (Double, Vec4 Word8)
load_zbuffer screen = (V.fromList (replicate ((width_i screen)*(height_i screen)) (0.0, toVec4 0 0 0 0))) 

load_shadowbuffer :: Screen -> V.Vector (Double, Vec4 Word8)
load_shadowbuffer screen = (V.fromList (replicate ((width_i screen)*(height_i screen)) (0.0, toVec4 255 255 255 255))) 

load_rasteriser :: Model -> Screen -> Camera -> Light -> Rasteriser
load_rasteriser  model screen camera light = Rasteriser zbuffer depthbuffer model screen camera light 
                                        where zbuffer = load_zbuffer screen
                                              depthbuffer = load_shadowbuffer screen


process_triangle :: Rasteriser -> Shader -> Int -> IO (Rasteriser, Shader)
process_triangle ras shader iface  = do
                        let
                            ----------- VERTEX SHADER -----------
                            (screenVertices, shader') = 
                                (foldr (\nth_vertex (vert_coords, folded_shader) -> (let (vertex, folded_shader') = vertex_shade folded_shader (ras) iface nth_vertex  :: ( (Vec4 Double), Shader)
                                                                                         
                                                                                    in  ((vertex:vert_coords), folded_shader'))) (([]), shader) [0, 1, 2]) :: ( [Vec4 Double], Shader)

                            (screenVert0:screenVert1:screenVert2:_) = screenVertices
                      
                            (screenVertices', shader'') =  (toVec3 screenVert0 screenVert1 screenVert2, shader')  :: (Mat34 Double, Shader)
                 
                            -----------   SET BBOX -----------

                            fetchx i = getElem 0 (getElem i screenVertices' )
                            fetchy i = getElem 1 (getElem i screenVertices' )
                            fetchw i = getElem 3 (getElem i screenVertices' )

                            bboxmin = foldr (\(x, y) (x', y') -> ((min x x'),(min y y')) )  
                                            (1000000.0, 1000000.0)
                                            [ (  (fetchx i)/(fetchw i) ,   (fetchy i)/(fetchw i)  ) |  i <- [0,1,2] ]

                            bboxmax = foldr (\(x, y) (x', y') -> ((max x x'),(max y y')) )  
                                            ((-1000000.0), (-1000000.0))   
                                            [ (  (fetchx i)/(fetchw i) ,   (fetchy i)/(fetchw i) ) |  i <- [0,1,2] ]
                        
                            --------------------------------------
                            

                        (updated_rasteriser, updated_shader) <- (draw_triangle ras shader'' screenVertices'   (floor $ fst bboxmin, floor $ fst bboxmax)   
                                                                                                                        (floor $ snd bboxmin, floor $ snd bboxmax) 
                                                                                                                        (floor $ fst bboxmin) 
                                                                                                                        (floor $ snd bboxmin) )
                        return $ (updated_rasteriser, updated_shader)


-- #             Screen ->  Triangle Vertices   ->  Z-Buffer                     
draw_triangle :: Rasteriser -> Shader -> Vec3 (Vec4 Double) ->  (Int, Int) -> (Int, Int) -> Int -> Int ->  IO (Rasteriser, Shader)
draw_triangle ras shader screen_vertices (bbox_min_x, bbox_max_x) (bbox_min_y, bbox_max_y) px py
    | (py > bbox_max_y)                      = (return ((ras, shader)))
    | (px > bbox_max_x)                      = draw_triangle ras shader screen_vertices (bbox_min_x, bbox_max_x) (bbox_min_y, bbox_max_y) bbox_min_x (py + 1)
    | otherwise = do 
                let
                    -- Screen Coordinates
                    (vertex_0, vertex_1, vertex_2) = fromVec3 screen_vertices
                    ((x0,y0,z0,w0),(x1,y1,z1,w1),(x2,y2,z2,w2)) = mapTuple3 fromVec4D (vertex_0, vertex_1, vertex_2)
                
                    -- Coordinate Attributes
                    barycentric_inputs = (projectVec4to2D (mult_v4_num vertex_0 (1.0/w0) ) , projectVec4to2D (mult_v4_num vertex_1  (1.0/w1) ), projectVec4to2D (mult_v4_num vertex_2 (1.0/w2))) 
                    pixel = (toVec2D (to_double px) (to_double py) )
                    maybeBary = barycentric barycentric_inputs (toVec2D (to_double px) (to_double py) )

                -- print maybeBary
                case maybeBary of   Nothing   -> (draw_triangle ras shader screen_vertices (bbox_min_x, bbox_max_x) (bbox_min_y, bbox_max_y) (px + 1) py)
                                    Just bary -> (    do
                                                
                                                let z = (z0 * getElem 0 bary) + (z1 * getElem 1 bary) + (z2 * getElem 2 bary) 
                                                    w = (w0 * getElem 0 bary) + (w1 * getElem 1 bary) + (w2 * getElem 2 bary) 
                                                    -- frag_depth = (z/w) :: Double
                                                    (_, _, frag_depth) = (fromVec3D $ multmv (getCurrentTri shader) bary) :: (Double, Double, Double)
                                                    (updateBuffer, getBuffer) = case shader of  (CameraShader {..}) -> ( (\(new_buff, ras) -> ras {getZBuffer = new_buff} ) , (\ras -> getZBuffer ras))
                                                                                                (DepthShader  {..}) -> ( (\(new_buff, ras) -> ras {getDepthBuffer = new_buff} ) , (\ras -> getDepthBuffer ras))

                                                if ( (fst ((getBuffer ras) V.! (px + py * screenWidth_i))) > frag_depth )
                                                then  (draw_triangle ras shader screen_vertices (bbox_min_x, bbox_max_x) (bbox_min_y, bbox_max_y) (px + 1) py)
                                                else ( do
                                                    (updated_ras , updated_shader) <- fragment_shade shader ras bary (px + py * screenWidth_i)

                                                    
                                                    draw_triangle updated_ras updated_shader screen_vertices (bbox_min_x, bbox_max_x) (bbox_min_y, bbox_max_y) (px+1) py)) 
                                            
                                                          
      

render_screen :: Rasteriser -> Shader -> Int -> Int -> IO ()
render_screen ras shader px py = do
            
                let screen = getScreen ras
                    index = px + py * (width_i (getScreen ras))



                let rgba =  case shader of  (CameraShader {..}) -> vec4ToV4 $ snd $ (getZBuffer ras) V.! index
                                            (DepthShader  {..}) -> vec4ToV4 $ snd $ (getDepthBuffer ras) V.! index
                
                sdl_put_pixel screen (V2 (fromIntegral px) ( fromIntegral py)) (rgba) 

                                        









-- order_min_x :: (Vec3 Double, Vec3 Double) -> (Vec2 Double, Vec2 Double) -> ((Vec3 Double, Vec3 Double), (Vec2 Double, Vec2 Double))
-- order_min_x (Vec3 vAx vAy vAz, Vec3 vBx vBy vBz) (Vec2 vAu vAv, Vec2 vBu vBv)
--     | (vAx > vBx) = ((Vec3 vBx vBy vBz, Vec3 vAx vAy vAz), (Vec2 vBu vBv, Vec2 vAu vAv))
--     | otherwise   = ((Vec3 vAx vAy vAz, Vec3 vBx vBy vBz), (Vec2 vAu vAv, Vec2 vBu vBv))

-- order_vertices :: (Vec3 Double, Vec3 Double, Vec3 Double) -> (Vec2 Double, Vec2 Double, Vec2 Double) -> Int ->  ((Vec3 Double, Vec3 Double, Vec3 Double), (Vec2 Double, Vec2 Double, Vec2 Double))
-- order_vertices (Vec3 v0x v0y v0z, Vec3 v1x v1y v1z, Vec3 Vec2x Vec2y Vec2z)  (Vec2 v0u v0v, Vec2 v1u v1v, Vec2 Vec2u Vec2v) stage
--     | stage == 0 = if (v0y > v1y)   then order_vertices (Vec3 v1x v1y v1z, Vec3 v0x v0y v0z, Vec3 Vec2x Vec2y Vec2z)  (Vec2 v1u v1v, Vec2 v0u v0v, Vec2 Vec2u Vec2v) 1 
--                                     else order_vertices (Vec3 v0x v0y v0z, Vec3 v1x v1y v1z, Vec3 Vec2x Vec2y Vec2z)  (Vec2 v0u v0v, Vec2 v1u v1v, Vec2 Vec2u Vec2v) 1
--     | stage == 1 = if (v0y > Vec2y)   then order_vertices (Vec3 Vec2x Vec2y Vec2z, Vec3 v1x v1y v1z, Vec3 v0x v0y v0z)  (Vec2 Vec2u Vec2v, Vec2 v1u v1v, Vec2 v0u v0v) 2
--                                     else order_vertices (Vec3 v0x v0y v0z, Vec3 v1x v1y v1z, Vec3 Vec2x Vec2y Vec2z)  (Vec2 v0u v0v, Vec2 v1u v1v, Vec2 Vec2u Vec2v) 2
--     | stage == 2 = if (v1y > Vec2y)   then order_vertices (Vec3 v0x v0y v0z, Vec3 Vec2x Vec2y Vec2z, Vec3 v1x v1y v1z)  (Vec2 v0u v0v, Vec2 Vec2u Vec2v, Vec2 v1u v1v) 3
--                                     else order_vertices (Vec3 v0x v0y v0z, Vec3 v1x v1y v1z, Vec3 Vec2x Vec2y Vec2z)  (Vec2 v0u v0v, Vec2 v1u v1v, Vec2 Vec2u Vec2v) 3
--     | otherwise = ((Vec3 v0x v0y v0z, Vec3 v1x v1y v1z, Vec3 Vec2x Vec2y Vec2z), (Vec2 v0u v0v, Vec2 v1u v1v, Vec2 Vec2u Vec2v))

-- order_min_x_i :: (Vec3 Int, Vec3 Int) -> (Vec2 Int, Vec2 Int) -> ((Vec3 Int, Vec3 Int), (Vec2 Int, Vec2 Int))
-- order_min_x_i (Vec3 vAx vAy vAz, Vec3 vBx vBy vBz) (Vec2 vAu vAv, Vec2 vBu vBv)
--     | (vAx > vBx) = ((Vec3 vBx vBy vBz, Vec3 vAx vAy vAz), (Vec2 vBu vBv, Vec2 vAu vAv))
--     | otherwise   = ((Vec3 vAx vAy vAz, Vec3 vBx vBy vBz), (Vec2 vAu vAv, Vec2 vBu vBv))

-- order_vertices_i :: Vec3 (Vec3 Int) -> Vec3 (Vec2 Int) -> Int -> (Vec3 (Vec3 Int), Vec3 (Vec2 Int))
-- order_vertices_i (Vec3 (Vec3 v0x v0y v0z) (Vec3 v1x v1y v1z) (Vec3 Vec2x Vec2y Vec2z))  (Vec3 (Vec2 v0u v0v) (Vec2 v1u v1v) (Vec2 Vec2u Vec2v)) stage
--     | stage == 0 = if (v0y > v1y)   then order_vertices_i (Vec3 (Vec3 v1x v1y v1z) (Vec3 v0x v0y v0z) (Vec3 Vec2x Vec2y Vec2z)) (Vec3 (Vec2 v1u v1v) (Vec2 v0u v0v) (Vec2 Vec2u Vec2v)) 1 
--                                     else order_vertices_i (Vec3 (Vec3 v0x v0y v0z) (Vec3 v1x v1y v1z) (Vec3 Vec2x Vec2y Vec2z)) (Vec3 (Vec2 v0u v0v) (Vec2 v1u v1v) (Vec2 Vec2u Vec2v)) 1
--     | stage == 1 = if (v0y > Vec2y)   then order_vertices_i (Vec3 (Vec3 Vec2x Vec2y Vec2z) (Vec3 v1x v1y v1z) (Vec3 v0x v0y v0z)) (Vec3 (Vec2 Vec2u Vec2v) (Vec2 v1u v1v) (Vec2 v0u v0v)) 2
--                                     else order_vertices_i (Vec3 (Vec3 v0x v0y v0z) (Vec3 v1x v1y v1z) (Vec3 Vec2x Vec2y Vec2z)) (Vec3 (Vec2 v0u v0v) (Vec2 v1u v1v) (Vec2 Vec2u Vec2v)) 2
--     | stage == 2 = if (v1y > Vec2y)   then order_vertices_i (Vec3 (Vec3 v0x v0y v0z) (Vec3 Vec2x Vec2y Vec2z) (Vec3 v1x v1y v1z)) (Vec3 (Vec2 v0u v0v) (Vec2 Vec2u Vec2v) (Vec2 v1u v1v)) 3
--                                     else order_vertices_i (Vec3 (Vec3 v0x v0y v0z) (Vec3 v1x v1y v1z) (Vec3 Vec2x Vec2y Vec2z)) (Vec3 (Vec2 v0u v0v) (Vec2 v1u v1v) (Vec2 Vec2u Vec2v)) 3
--     | otherwise = (Vec3 (Vec3 v0x v0y v0z) (Vec3 v1x v1y v1z) (Vec3 Vec2x Vec2y Vec2z), Vec3 (Vec2 v0u v0v)(Vec2 v1u v1v)(Vec2 Vec2u Vec2v))
                                                                            
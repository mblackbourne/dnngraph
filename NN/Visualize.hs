{-# LANGUAGE OverloadedStrings #-}
module NN.Visualize(visualize, visualizeWith, render, png, pdf, scaled, defaultNNParams) where

import           Gen.Caffe.AccuracyParameter            as AP
import           Gen.Caffe.ConvolutionParameter         as CP
import           Gen.Caffe.InnerProductParameter        as IP
import           Gen.Caffe.LayerParameter               as LP
import           Gen.Caffe.PoolingParameter             as PP
import           Gen.Caffe.PoolingParameter.PoolMethod  as PP

import           Data.GraphViz
import           Data.GraphViz.Attributes.Colors.Brewer
import           Data.GraphViz.Attributes.Complete
import qualified Data.Text.Lazy                         as L

import           Control.Lens
import           Data.Graph.Inductive.Graph
import           Formatting
import           NN.DSL

type NetVizParams = GraphvizParams Node LayerParameter () () LayerParameter

data LayerDetail = Type | TypeWithDims

defaultNNParams :: NetVizParams
defaultNNParams =
    nonClusteredParams {
  -- Let's visualize neural networks from the bottom up
  globalAttributes = [GraphAttrs [RankDir FromBottom]],
  fmtNode = fmtLabelParameter TypeWithDims
}

scaled :: (LayerParameter -> Double) -> NetVizParams
scaled f = defaultNNParams { fmtNode = setSize }
    where
      setSize n@(_, lp) = fmtNode defaultNNParams n ++ [Width width', Height height']
          where
            width' = 0.75 * scale
            height' = 0.5 * scale
            scale = f lp

visualizeWith :: NetVizParams -> Net -> DotGraph Node
visualizeWith = graphToDot

visualize :: Net -> DotGraph Node
visualize = visualizeWith defaultNNParams

render :: GraphvizOutput -> FilePath -> DotGraph Node -> IO FilePath
render fmt path g = runGraphviz g fmt path

pdf, png :: FilePath -> DotGraph Node -> IO FilePath
png = render Png
pdf = render Pdf

fmtLabelParameter :: LayerDetail -> (Node, LayerParameter) -> [Attribute]
fmtLabelParameter level (_, lp) =
    [FontName "Source Code Pro",
     textLabel label,
     style filled,
     fillColor color']
    where
      maxColors = 8
      idx = ((+1) . (`mod` maxColors) . fromEnum . layerTy) lp
      scheme = BScheme Pastel2 (fromIntegral maxColors)
      color' = BC scheme (fromIntegral idx)
      label = pprint level lp

pprint :: LayerDetail -> LayerParameter -> L.Text
pprint Type = L.pack . asCaffe . layerTy
pprint TypeWithDims = dimensions

dimensions :: LayerParameter -> L.Text
dimensions lp = params ty'
    where
      ty' = layerTy lp
      -- Conv 128x3x3 s2
      params Conv = L.unlines ["Conv",
                               format (int % "x" % int % "x" % int % " s" % int) o sz sz st]
          where
            cp f = lp ^?! convolution_param._Just ^?! f._Just
            sz = cp CP.kernel_size
            st = cp CP.stride
            o = cp CP.num_output
      params IP = L.unlines ["FC", format int ip']
          where
            ip' = lp ^?! inner_product_param._Just ^?! IP.num_output._Just
      -- 3x3 s2
      params Pool = L.unlines [pty', format (int % "x" % int % " s" % int) sz sz st]
          where
            pp f = lp ^?! pooling_param._Just ^?! f._Just
            pty' = case pp pool of
               MAX -> "MaxPool"
               AVE -> "AveragePool"
               STOCHASTIC -> "StochasticPool"
            sz = pp PP.kernel_size
            st = pp PP.stride
      params Accuracy = format ("Top-" % int) k
          where
            k = lp ^?! accuracy_param._Just ^?! top_k._Just
      params _ = (L.pack . asCaffe) ty'

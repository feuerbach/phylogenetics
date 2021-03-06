-- | Calculate the likelihood of the tree given the data
module Phylogenetics.Likelihood_v1 where

import qualified Data.Vector.Unboxed as VU
import Data.Word
import Data.Tuple.Homogenous
import qualified Numeric.LinearAlgebra.Data as Matrix

import Phylogenetics.Types as Phylo

-- | The likelihood of a subtree conditional on the state of its root
-- (a.k.a. the «partial likelihood»).
--
-- If the subtree is a leaf, then it's represented by its character state.
--
-- Otherwise, it's the likelihood conditional on the (unobserved) character
-- state of its root, and is represented as a vector of likelihoods for
-- each state of its root.
data PostOrder
  = LeafCL Word8
  | BinCL (VU.Vector Double)

-- | The full log-likelihood, summed over all sites
logLikelihood
  :: Problem
  -> BranchLengths
  -> Double
logLikelihood prob@(Problem _rate_mx obs _tree) bls = sum $ do
  site <- [0 .. numOfSites obs - 1]
  return . log $ likelihood1 prob bls site

-- | Likelihood for a single site
likelihood1
  :: Problem
  -> BranchLengths
  -> Int -- ^ the index of the site
  -> Double
likelihood1 (Problem rate_mx obs topo) bls site =
  case go topo of
    LeafCL{} -> 1
    BinCL ls -> VU.sum ls / numOfStates rate_mx
  where
  -- Given a (sub)tree topology, return, for each root state,
  -- the probability of observations at the tips
  go :: Topology -> PostOrder
  go = \case
    Leaf node_id ->
      LeafCL $ (characters obs ! node_id) `VU.unsafeIndex` site
    Bin _ sub1 sub2 ->
      let
        subs :: Tuple2 Topology
        subs = tuple2 sub1 sub2
      in
        calculatePostOrder rate_mx bls subs (go <$> subs)

-- | Calculate the post-order traversal of a tree given its values at the subtrees
calculatePostOrder
  :: RateMatrix
  -> BranchLengths
  -> Tuple2 Topology
    -- ^ the subtrees
  -> Tuple2 PostOrder
    -- ^ likelihoods of the subtrees
  -> PostOrder
    -- ^ likelihood of the subtree
calculatePostOrder rate_mx bls subs sub_cls = BinCL . VU.fromList $ do
  -- iterate over the possible characters at the root
  root_c <- [0..numOfStates rate_mx - 1]
  return . product $ do
    -- iterate over the two subtrees (applicative do)
    sub <- subs
    sub_cl <- sub_cls
    let
      bl = bls ! getNodeId sub
      transition_probs = transitionProbabilities rate_mx bl
    return $
      case sub_cl of
        LeafCL sub_c -> transition_probs `Matrix.atIndex` (root_c, fromIntegral sub_c)
        BinCL sub_liks -> sum $ do
          -- iterate over the subtree character
          sub_c <- [0..numOfStates rate_mx - 1]
          return $
            VU.unsafeIndex sub_liks (fromIntegral sub_c) *
            (transition_probs `Matrix.atIndex` (root_c, sub_c))

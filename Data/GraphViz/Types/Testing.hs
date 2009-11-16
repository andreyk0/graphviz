{- |
   Module      : Data.GraphViz.Types.Testing
   Description : Testing suite for Graphviz.
   Copyright   : (c) Ivan Lazar Miljenovic
   License     : 3-Clause BSD-style
   Maintainer  : Ivan.Miljenovic@gmail.com

-}
module Data.GraphViz.Types.Testing where

import Data.GraphViz.Types.Printing(PrintDot(..), renderDot)
import Data.GraphViz.Types.Parsing(ParseDot(..), runParser)

import Data.GraphViz.Attributes

import Test.QuickCheck

import Control.Monad(liftM, liftM2, liftM3, liftM4)
import Data.Word(Word8)

-- -----------------------------------------------------------------------------



printParse   :: (ParseDot a, PrintDot a, Eq a) => a -> Bool
printParse a = fst (runParser parse . renderDot $ toDot a) == a

-- -----------------------------------------------------------------------------
-- Defining Arbitrary instances

instance Arbitrary Word8 where
  arbitrary = arbitraryBoundedIntegral

instance Arbitrary URL where
  arbitrary = liftM UStr
              $ suchThat arbString (all notAngled)
    where
      -- Ensure it doesn't have any angled brackets
      notAngled = flip notElem ['<', '>']

instance Arbitrary ArrowType where
  arbitrary = liftM AType
              -- Arrow specifications have between 1 and 4 elements.
              $ resize 4 (listOf1 arbitrary)

instance Arbitrary ArrowShape where
  arbitrary = arbBounded

instance Arbitrary ArrowModifier where
  arbitrary = liftM2 ArrMod arbitrary arbitrary

instance Arbitrary ArrowFill where
  arbitrary = arbBounded

instance Arbitrary ArrowSide where
  arbitrary = arbBounded

instance Arbitrary AspectType where
  arbitrary = oneof [ liftM  RatioOnly arbitrary
                    , liftM2 RatioPassCount arbitrary posArbitrary
                    ]

instance Arbitrary Rect where
  arbitrary = liftM2 Rect arbitrary arbitrary

instance Arbitrary Point where
  -- Pretty sure points have to be positive...
  arbitrary = oneof [ liftM2 Point  posArbitrary posArbitrary
                    , liftM2 PointD posArbitrary posArbitrary
                    ]

instance Arbitrary Color where
  arbitrary = oneof [ liftM3 RGB  arbitrary arbitrary arbitrary
                    , liftM4 RGBA arbitrary arbitrary arbitrary arbitrary
                    , liftM3 HSV  zeroOne zeroOne zeroOne
                      -- Need to replace this when proper coloured
                      -- names are used
                    , liftM ColorName arbString
                    ]
    where
      zeroOne = choose (0,1)

instance Arbitrary ClusterMode where
  arbitrary = arbBounded

instance Arbitrary DirType where
  arbitrary = arbBounded

instance Arbitrary DEConstraints where
  arbitrary = arbBounded

instance Arbitrary DPoint where
  arbitrary = oneof [ liftM DVal arbitrary
                    , liftM PVal arbitrary
                    ]

instance Arbitrary ModeType where
  arbitrary = arbBounded

instance Arbitrary Model where
  arbitrary = arbBounded

instance Arbitrary Label where
  arbitrary = oneof [ liftM StrLabel arbString
                    , liftM URLLabel arbitrary
                    ]

instance Arbitrary Overlap where
  arbitrary = oneof [ simpleOverlap
                    , liftM PrismOverlap arbitrary
                    ]
    where
      -- Have to do this by hand since Overlap can't have Bounded and
      -- Enum instances
      simpleOverlap = elements [ KeepOverlaps
                               , RemoveOverlaps
                               , ScaleOverlaps
                               , ScaleXYOverlaps
                               , CompressOverlap
                               , VpscOverlap
                               , IpsepOverlap
                               ]

instance Arbitrary LayerList where
  arbitrary = do fst <- arbLayerName
                 oths <- listOf $ liftM2 (,) arbLayerSep arbLayerName
                 return $ LL fst oths

instance Arbitrary LayerRange where
  arbitrary = oneof [ liftM  LRID arbitrary
                    , liftM3 LRS arbitrary arbLayerSep arbitrary
                    ]
    where
      arbLayerSep = listOf1 (elements defLayerSep)

instance Arbitrary LayerID where
  arbitrary = oneof [ return AllLayers
                    , liftM LRInt arbitrary
                    , liftM LRName arbLayerName
                    ]

instance Arbitrary OutputMode where
  arbitrary = arbBounded

instance Arbitrary Pack where
  arbitrary = oneof [ return DoPack
                    , return DontPack
                    , liftM PackMargin arbitrary
                    ]

instance Arbitrary PackMode where
  arbitrary = oneof [ return PackNode
                    , return PackClust
                    , return PackGraph
                    , liftM3 PackArray arbitrary arbitrary arbitrary
                    ]

instance Arbitrary Pos where
  arbitrary = oneof [ liftM PointPos arbitrary
                    , liftM SplinePos (listOf1 arbitrary)
                    ]

instance Arbitrary Spline where
  arbitrary = liftM3 Spline arbitrary arbitrary
              -- list of points must have length of 1 mod 3
              $ suchThat arbitrary ((==) 1 . flip mod 3 . length)

instance Arbitrary EdgeType where
  arbitrary = arbBounded

instance Arbitrary PageDir where
  arbitrary = arbBounded

instance Arbitrary QuadType where
  arbitrary = arbBounded

instance Arbitrary Root where
  arbitrary = oneof [ return IsCentral
                    , return NotCentral
                    , liftM NodeName arbString
                    ]

instance Arbitrary RankType where
  arbitrary = arbBounded

instance Arbitrary RankDir where
  arbitrary = arbBounded

instance Arbitrary Shape where
  arbitrary = arbBounded

instance Arbitrary SmoothType where
  arbitrary = arbBounded

instance Arbitrary StartType where
  arbitrary = oneof [ liftM  StartStyle arbitrary
                    , liftM  StartSeed arbitrary
                    , liftM2 StartStyleSeed arbitrary arbitrary
                    ]

instance Arbitrary STStyle where
  arbitrary = arbBounded

instance Arbitrary StyleItem where
  arbitrary = liftM2 SItem arbitrary (listOf arbStyleName)

instance Arbitrary StyleName where
  arbitrary = oneof [ defaultStyles
                    , liftM DD arbStyleName
                    ]
    where
      defaultStyles = elements [ Dashed
                               , Dotted
                               , Bold
                               , Invisible
                               , Filled
                               , Diagonals
                               , Rounded
                               ]

instance Arbitrary PortPos where
  arbitrary = liftM PP arbitrary

instance Arbitrary CompassPoint where
  arbitrary = arbBounded

instance Arbitrary ViewPort where
  arbitrary = liftM4 VP arbitrary arbitrary arbitrary arbitrary

instance Arbitrary FocusType where
  arbitrary = oneof [ liftM XY arbitrary
                    , liftM NodeFocus arbString
                    ]

instance Arbitrary VerticalPlacement where
  arbitrary = arbBounded

instance Arbitrary ScaleType where
  arbitrary = arbBounded

instance Arbitrary Justification where
  arbitrary = arbBounded

instance Arbitrary Ratios where
  arbitrary = oneof [ liftM AspectRatio posArbitrary
                    , namedRats
                    ]
    where
      namedRats = elements [ FillRatio
                           , CompressRatio
                           , ExpandRatio
                           , AutoRatio
                           ]

-- -----------------------------------------------------------------------------
-- Helper Functions

fromPositive              :: Positive a -> a
fromPositive (Positive a) = a

posArbitrary :: (Arbitrary a, Num a, Ord a) => Gen a
posArbitrary = liftM fromPositive arbitrary

arbString :: Gen String
arbString = listOf1 arbitrary

arbBounded :: (Bounded a, Enum a) => Gen a
arbBounded = elements [minBound .. maxBound]

arbLayerSep :: Gen [Char]
arbLayerSep = listOf1 (elements defLayerSep)

arbLayerName :: Gen String
arbLayerName = suchThat arbString (all notLayerSep)
    where
      notLayerSep = flip notElem defLayerSep

arbStyleName :: Gen String
arbStyleName = suchThat arbString (all notBrackCom)
  where
    notBrackCom = flip notElem ['(', ')', ',', ' ']
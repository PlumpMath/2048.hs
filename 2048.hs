{-# LANGUAGE OverloadedStrings #-}

-- | Quick crack at a minimal 2048 in haskell

module Main where

import Control.Monad.Writer
import Data.Maybe
import Data.List
import System.Random

import qualified Data.Text as T

import System.Console.Haskeline

type Cell  = Maybe Int
type Row   = [Cell]
type Board = [Row]
type Score = Int
data Direction = East | West | North | South deriving (Show, Eq)

-- | points earned and whether or not anything changed
data ShiftResult = ShiftResult (Sum Score) Any deriving (Show)
instance Monoid ShiftResult where
    mempty = ShiftResult (Sum 0) (Any False)
    mappend (ShiftResult a b) (ShiftResult x y) = ShiftResult (a <> x) (b <> y)

data MoveOutcome = Lose | Win | Active
data RoundResult = RoundResult Score MoveOutcome Board 

showBoard :: Board -> String
showBoard = T.unpack . T.unlines . fmap formatRow
    where formatRow = T.intercalate "|" . fmap (T.center 4 ' ' . formatCell)
          formatCell (Just x) = T.pack $ show x
          formatCell _ = mempty

shiftRow :: Row -> Writer ShiftResult Row
shiftRow row = do
    os <- liftM (++ nothings) $ sumPairs justs
    tell $ ShiftResult (Sum 0) (Any $ os /= row)
    return os
    where (justs, nothings) = partition isJust row
          sumPairs (Just x:Just y:zs) | x == y = do
            let total = x + y
            tell $ ShiftResult (Sum total) (Any True)
            rest <- sumPairs zs
            return $ Just total : rest ++ [Nothing]
          sumPairs (x:xs) = liftM (x :) $ sumPairs xs
          sumPairs [] = return []

shiftBoard :: Direction -> Board -> (Board, ShiftResult)
shiftBoard direction = runWriter . case direction of
    West  -> goWest
    East  -> goEast
    North -> liftM transpose . goWest . transpose
    South -> liftM transpose . goEast . transpose
    where goWest = mapM shiftRow
          goEast = mapM $ liftM reverse . shiftRow . reverse

emptyBoard :: Int -> Board
emptyBoard n = replicate n $ replicate n Nothing

-- | coords of available spaces
available :: Board -> [(Int, Int)]
available = concat . zipWith (zip . repeat) [0..] . fmap (elemIndices Nothing)

--  ew
update :: Board -> (Int, Int) -> Cell -> Board
update board (x, y) val = newBoard
    where (rs, r:rs') = splitAt x board
          (cs, _:cs') = splitAt y r
          newRow = cs <> [val] <> cs'
          newBoard = rs <> [newRow] <> rs'

insertRandom :: Board -> IO (Maybe Board)
insertRandom board
    | null holes = return Nothing
    | otherwise = do
        pos <- liftM (holes !!) $ randomRIO (0, length holes - 1)
        coin <- randomRIO (0, 1) :: IO Float
        let newCell = Just $ if coin < 0.9 then 2 else 4
        return . Just $ update board pos newCell
    where holes = available board

winner :: Cell -> Board -> Bool
winner winning = elem winning . concat

gameRound :: Cell -> Direction -> Board -> IO RoundResult
gameRound goal direction board =
    let (newBoard, ShiftResult (Sum newPoints) (Any change)) =
            shiftBoard direction board
        result = RoundResult newPoints
    in if not change 
        then return $ if null $ available newBoard
            then result Lose newBoard
            else result Active newBoard
        else if winner goal newBoard
            then return $ result Win newBoard
            else do
                randoBoard <- liftIO $ insertRandom newBoard
                case randoBoard of
                    Nothing -> return $ result Lose newBoard
                    Just b  -> return $ result Active b

runGame :: Cell -> Board -> Int -> InputT IO ()
runGame goal board score = do
    liftIO . putStrLn $ showBoard board
    input <- getInputChar "wasd: "
    liftIO $ putStrLn ""
    
    let direction = case input of
         Just 'w' -> Just North
         Just 'a' -> Just West
         Just 's' -> Just South
         Just 'd' -> Just East
         _ -> Nothing

    case direction of
        Nothing ->
            runGame goal board score
        Just dir -> do
            RoundResult newPoints moveOutcome newBoard <-
                liftIO $ gameRound goal dir board
            let totalScore = newPoints + score
            case moveOutcome of
                Lose -> liftIO $ 
                    putStrLn $ "You lose with " ++ show totalScore ++ " points."
                Win -> liftIO $ 
                    putStrLn $ "You win with " ++ show totalScore ++ " points!"
                Active -> do
                    liftIO $ do
                        putStrLn $ "You earned " ++ show newPoints ++ " points."
                        putStrLn $ "Total score is " ++ show totalScore ++ " points."
                    runGame goal newBoard totalScore

main :: IO ()
main = do
    let size = 4
        goal = Just 2048

    Just startBoard <- insertRandom . fromJust =<< insertRandom (emptyBoard size)

    putStrLn "Use 'w', 'a', 's', and 'd' to move."
    runInputT defaultSettings $ runGame goal startBoard 0

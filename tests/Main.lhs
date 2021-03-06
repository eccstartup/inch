> module Main where

> import Control.Applicative
> import Control.Monad.State
> import Data.List
> import System.Directory
> import System.Exit

> import Language.Inch.Context
> import Language.Inch.Syntax
> import Language.Inch.ModuleSyntax
> import Language.Inch.Parser
> import Language.Inch.PrettyPrinter
> import Language.Inch.ProgramCheck
> import Language.Inch.Erase
> import Language.Inch.File (checkFile, readImports)

> main :: IO ()
> main = checks "examples/" >> erases "examples/"

> checks :: FilePath -> IO ()
> checks = testDir check

> erases :: FilePath -> IO ()
> erases = testDir erase

> testDir :: (FilePath -> IO ()) -> FilePath -> IO ()
> testDir f d = do
>     fns <- sort . filter (".hs" `isSuffixOf`) <$> getDirectoryContents d
>     mapM_ (f . (d ++)) fns

> check :: FilePath -> IO ()
> check fn = do
>     putStrLn $ "TEST " ++ show fn
>     s <- readFile fn
>     (md, _) <- checkFile fn s 
>     putStrLn $ renderMe (fog md)

> erase :: FilePath -> IO ()
> erase fn = do
>     putStrLn $ "TEST " ++ show fn
>     s <- readFile fn
>     (md, st) <- checkFile fn s
>     case evalStateT (eraseModule md) st of
>         Right md'  -> putStrLn $ renderMe (fog md')
>         Left err   -> putStrLn ("erase error:\n" ++ renderMe err) >> exitFailure




> test :: (a -> String) -> (a -> Either String String)
>             -> [a] -> Int -> Int -> IO (Int, Int)
> test _ _ [] yes no = do
>     putStrLn $ "Passed " ++ show yes ++ " tests, failed "
>                          ++ show no ++ " tests."
>     return (yes, no)
> test g f (x:xs) yes no = do
>     putStrLn $ "TEST\n" ++ g x
>     case f x of
>         Right s  -> putStrLn ("PASS\n" ++ s) >> test g f xs (yes+1) no
>         Left s   -> putStrLn ("FAIL\n" ++ s) >> test g f xs yes (no+1)


> roundTripTest, parseCheckTest, eraseCheckTest :: IO ()
> roundTripTest  = void $ test id roundTrip roundTripTestData 0 0
> parseCheckTest = do
>     ds <- readImports "examples/" []
>     void $ test fst (parseCheck ds) parseCheckTestData 0 0
> eraseCheckTest = do
>     ds <- readImports "examples/" []
>     void $ test id (eraseCheck ds) (map fst . filter snd $ parseCheckTestData) 0 0

> roundTrip :: String -> Either String String
> roundTrip s = case parseModule "roundTrip" s of
>     Right md  ->
>         let s' = renderMe md in
>         case parseModule "roundTrip2" s' of
>             Right md'
>               | md == md'  -> Right $ renderMe md'
>               | otherwise      -> Left $ "Round trip mismatch:"
>                     ++ "\n" ++ s' ++ "\n" ++ renderMe md'
>                     ++ "\n" ++ show md ++ "\n" ++ show md'
>                     -- ++ "\n" ++ show prog ++ "\n" ++ show prog'
>             Left err -> Left $ "Round trip re-parse:\n"
>                                    ++ s' ++ "\n" ++ show err
>     Left err -> Left $ "Initial parse:\n" ++ s ++ "\n" ++ show err

> parseCheck :: [STopDeclaration] -> (String, Bool) -> Either String String
> parseCheck ds (s, b) = case parseModule "parseCheck" s of
>     Right md   -> case evalStateT (checkModule md ds) initialState of
>         Right md'
>             | b          -> Right $ "Accepted good program:\n"
>                                     ++ renderMe (fog md') ++ "\n"
>             | otherwise  -> Left $ "Accepted bad program:\n"
>                                     ++ renderMe (fog md') ++ "\n"
>         Left err
>             | b          -> Left $ "Rejected good program:\n"
>                             ++ renderMe md ++ "\n" ++ renderMe err ++ "\n"
>             | otherwise  -> Right $ "Rejected bad program:\n"
>                             ++ renderMe md ++ "\n" ++ renderMe err ++ "\n"
>     Left err  -> Left $ "Parse error:\n" ++ s ++ "\n" ++ show err ++ "\n"

> eraseCheck :: [STopDeclaration] -> String -> Either String String
> eraseCheck ds s = case parseModule "eraseCheck" s of
>     Right md   -> case runStateT (checkModule md ds) initialState of
>         Right (md', st) -> case evalStateT (eraseModule md') st of
>             Right md'' -> case evalStateT (checkModule (fog md'') ds) initialState of
>                 Right md''' -> case parseModule "eraseCheckRoundTrip" (renderMe (fog md''')) of
>                     Right md'''' -> Right $ "Erased program:\n" ++ renderMe md''''
>                     Left err -> Left $ "Erased program failed to round-trip:\n" ++ renderMe (fog md''') ++ "\n" ++ show err
>                 Left err -> Left $ "Erased program failed to type check:\n" ++ renderMe (fog md'') ++ "\n" ++ renderMe err
>             Left err        -> Left $ "Erase error:\n" ++ s ++ "\n" ++ renderMe err ++ "\n"

>         Left err -> Right $ "Skipping rejected program:\n"
>                             ++ s ++ "\n" ++ renderMe err ++ "\n"
>     Left err  -> Left $ "Parse error:\n" ++ s ++ "\n" ++ show err ++ "\n"


> roundTripTestData :: [String]
> roundTripTestData = 
>   "f = x" :
>   "f = a b" :
>   "f = \\ x -> x" :
>   "f = \\ x y z -> a b c" :
>   "f = a\ng = b" :
>   "f = x (y z)" :
>   "f = a\n b" :
>   "f = x :: a" :
>   "f = x :: a -> b -> c" :
>   "f = x :: Foo" :
>   "f = x :: Foo a" :
>   "f = x :: (->)" :
>   "f = x :: (->) a b" :
>   "f = x :: F a -> G b" :
>   "f = \\ x -> x :: a -> b" :
>   "f = (\\ x -> x) :: a -> b" :
>   "f = x :: forall (a :: *) . a" :
>   "f = x :: forall a . a" :
>   "f = x :: forall a b c . a" :
>   "f = x :: forall (a :: Num)b(c :: * -> *)(d :: *) . a" :
>   "f = x :: forall a b . pi (c :: Num) d . b -> c" :
>   "f = x :: forall (a b c :: *) . a" :
>   "f x y z = x y z" :
>   "f Con = (\\ x -> x) :: (->) a a" :
>   "f Con = \\ x -> x :: (->) a" :
>   "f = f :: (forall a . a) -> (forall b. b)" : 
>   "f x y = (x y :: Nat -> Nat) y" :
>   "plus Zero n = n\nplus (Suc m) n = Suc (plus m n)" :
>   "data Nat where Zero :: Nat\n Suc :: Nat -> Nat" :
>   "data Foo :: (* -> *) -> (Num -> *) where Bar :: forall (f :: * -> *)(n :: Num) . (Vec (f Int) n -> a b) -> Foo f n" :
>   "data Vec :: Num -> * -> * where\n Nil :: forall a. Vec 0 a\n Cons :: forall a (m :: Num). a -> Vec m a -> Vec (m+1) a" :
>   "huh = huh :: Vec (-1) a" :
>   "heh = heh :: Vec m a -> Vec n a -> Vec (m-n) a" :
>   "hah = hah :: Foo 0 1 (-1) (-2) m (m+n) (m+1-n+2)" :
>   "f :: a -> a\nf x = x" :
>   "f :: forall a. a -> a\nf x = x" :
>   "f :: forall a.\n a\n -> a\nf x = x" :
>   "f :: forall m n. m <= n => Vec m\nf = f" :
>   "f :: forall m n. (m) <= (n) => Vec m\nf = f" :
>   "f :: forall m n. (m + 1) <= (2 + n) => Vec m\nf = f" :
>   "f :: forall m n. (m <= n, m <= n) => Vec m\nf = f" :
>   "f :: forall m n. (m <= n, (m + 1) <= n) => Vec m\nf = f" :
>   "f :: forall m n. (0 <= n, n <= 10) => Vec m\nf = f" :
>   "f :: forall m n. (m + (- 1)) <= n => Vec m\nf = f" :
>   "f :: forall m n. 0 <= -1 => Vec m\nf = f" :
>   "f :: forall m n. 0 <= -n => Vec m\nf = f" :
>   "f :: forall m n. m ~ n => Vec m\nf = f" :
>   "f :: forall m n. m ~ (n + n) => Vec m\nf = f" :
>   "f :: pi (m :: Num) . Int\nf {0} = Zero\nf {n+1} = Suc f {n}" :
>   "f x _ = x" :
>   "f :: forall a. pi (m :: Num) . a -> Vec a\nf {0} a = VNil\nf {n} a = VCons a (f {n-1} a)" :
>   "x = 0" :
>   "x = plus 0 1" :
>   "x = let a = 1\n in a" :
>   "x = let a = \\ x -> f x y\n in let b = 2\n  in a" :
>   "x = let y :: forall a. a -> a\n        y = \\ z -> z\n        f = f\n  in y" :
>   "f :: 0 <= 1 => Integer\nf = 1" :
>   "f :: forall (m n :: Num) . (m <= n => Integer) -> Integer\nf = f" :
>   "f :: 0 + m <= n + 1 => Integer\nf = f" :
>   "f :: 0 < 1 => a\nf = f" :
>   "f :: 0 > 1 => a\nf = f" :
>   "f :: (1 >= 0, a + 3 > 7) => a\nf = f" :
>   "f x | gr x 0 = x" :
>   "f x | {x > 0} = x" :
>   "f x | {x > 0, x ~ 0} = x" :
>   "f x | {x >= 0} = x\n    | {x <  0} = negate x" :
>   "f :: forall (m :: Nat) . g m\nf = f" :
>   "f = \\ {x} -> x" :
>   "f = \\ {x} y {z} -> plus x y" :
>   "x = case True of  False -> undefined\n                  True -> 3" :
>   "x = case True of\n      False -> undefined\n      True -> 3" :
>   "x = case f 1 3 of\n    (Baz boo) -> boo boo" :
>   "x = case f 1 3 of\n     (Baz boo) -> boo boo\n     (Bif bof) -> bah" :
>   "x = case f 1 3 of\n    (Baz boo) | {2 ~ 3} -> boo boo" :
>   "x = case f 1 3 of\n     Baz boo | womble -> boo boo" :
>   "x = case f 1 3 of\n     Baz boo | {2 ~ 3} -> boo boo" :
>   "x = case a of\n  Wim -> Wam\n          Wom " :
>   "f :: g (abs (-6))\nf = f" :
>   "f :: g (signum (a + b))\nf = f" :
>   "f :: g (a ^ b + 3 ^ 2)\nf = f" :
>   "x = 2 + 3" :
>   "x = 2 - 3" :
>   "x = - 3" :
>   "f :: f ((*) 3 2) -> g (+)\nf = undefined" :
>   "x :: f min\nx = x" :
>   "data Foo where X :: Foo\n  deriving Show" :
>   "data Foo where\n    X :: Foo\n  deriving (Eq, Show)" :
>   "x :: [a]\nx = []" :
>   "y :: [Integer]\ny = 1 : 2 : [3, 4]" :
>   "x :: ()\nx = ()" :
>   "x :: (Integer, Integer)\nx = (3, 4)" :
>   "f () = ()\ng (x, y) = (y, x)" : 
>   "f [] = []\nf (x:y:xs) = x : xs" :
>   "f (_, x:_) = x" : 
>   "f [x,_] = x" : 
>   "x = a b : c d : e f" :
>   "f :: g (2 - 3)" :
>   "f xs = case xs of\n      [] -> []\n      y:ys -> ys" :
>   "a = \"hello\"" :
>   "b = 'w' : 'o' : 'r' : ['l', 'd']" :
>   "f (_:x) = x" :
>   "f (_ : x) = x" :
>   "x = y where y = 3" :
>   "x = y\n  where\n    y = z\n    z = x" :
>   "import A.B.C\nimport qualified B\nimport C (x, y)\nimport D as E hiding (z)\nimport F ()" :
>   "f (n + 1) = n" :
>   "(&&&) :: Bool -> Bool -> Bool\n(&&&) True x = x\n(&&&) False _ = False" :
>   "(&&&) :: Bool -> Bool -> Bool\nTrue &&& x = x\nFalse &&& _ = False" :
>   "f :: _a -> _a\nf x = x" :
>   "x = (case xs of\n    [] -> []\n    (:) x ys -> scanl f (f q x) ys)" :
>   "f :: forall (c :: Constraint) . c => Integer\nf = f" :
>   "f :: Dict ((<=) 2 3) -> Dict (2 <= 3)\nf x = x" :
>   "f :: Show a => a -> [Char]\nf x = show x" :
>   "class T a => S a" :
>   "class (T a) => S a" :
>   "class (T a, B a a) => S a" :
>   "class S a where\n  s :: a -> [Char]" :
>   "class S a where\n  s :: a -> [Char]\n  t :: Integer -> a" :
>   "instance S [Char] where\n  s x = x\n  f g = 0" :
>   "x, y :: Integer" :
>   "instance (S Integer, S a) => S [a] where" :
>   "instance Monad [] where" :
>   "type String = [Char]" :
>   "type F a b = b a" :
>   "type F (a :: *) (b :: * -> *) = b a" :
>   "instance N a 0 where" :
>   []



> vecDecl, vec2Decl, vec3Decl, natDecl :: String

> vecDecl = "data Vec :: Num -> * -> * where\n"
>   ++ "  Nil :: forall a (n :: Num). n ~ 0 => Vec n a\n"
>   ++ "  Cons :: forall a (m n :: Num). (0 <= m, n ~ (m + 1)) => a -> Vec m a -> Vec n a\n"
>   ++ " deriving (Eq, Show)\n"

> vec2Decl = "data Vec :: * -> Num -> * where\n"
>   ++ "  Nil :: forall a (n :: Num). n ~ 0 => Vec a n\n"
>   ++ "  Cons :: forall a (n :: Num). 1 <= n => a -> Vec a (n-1) -> Vec a n\n"

> vec3Decl = "data Vec :: Num -> * -> * where\n"
>   ++ "  Nil :: forall a . Vec 0 a\n"
>   ++ "  Cons :: forall a (n :: Num). 0 <= n => a -> Vec n a -> Vec (n+1) a\n"

> natDecl = "data Nat where\n Zero :: Nat\n Suc :: Nat -> Nat\n"

> parseCheckTestData :: [(String, Bool)]
> parseCheckTestData = 
>   ("f x = x", True) :
>   ("f = f", True) :
>   ("f = \\ x -> x", True) :
>   ("f = (\\ x -> x) :: forall a. a -> a", True) :
>   ("f x = x :: forall a b. a -> b", False) :
>   ("f = \\ x y z -> x y z", True) :
>   ("f x y z = x (y z)", True) :
>   ("f x y z = x y z", True) :
>   ("f x = x :: Foo", False) :
>   ("f :: a -> a\nf x = x", True) :
>   ("f :: a\nf = f", True) :
>   ("f :: forall a b. (a -> b) -> (a -> b)\nf = \\ x -> x", True) :
>   ("f :: (a -> b -> c) -> a -> b -> c\nf = \\ x y z -> x y z", True) :
>   ("f :: forall a b c. (b -> c) -> (a -> b) -> a -> c\nf x y z = x (y z)", True) :
>   ("f :: forall a b c. (a -> b -> c) -> a -> b -> c\nf x y z = x y z", True) :
>   (natDecl ++ "plus Zero n = n\nplus (Suc m) n = Suc (plus m n)\nf x = x :: Nat -> Nat", True) :
>   (natDecl ++ "f Suc = Suc", False) :
>   (natDecl ++ "f Zero = Zero\nf x = \\ y -> y", False) :
>   ("data List :: * -> * where\n Nil :: forall a. List a\n Cons :: forall a. a -> List a -> List a\nsing = \\ x -> Cons x Nil\nsong x y = Cons x (Cons (sing y) Nil)\nappend Nil ys = ys\nappend (Cons x xs) ys = Cons x (append xs ys)", True) :
>   ("f :: forall a b. (a -> b) -> (a -> b)\nf x = x", True) :
>   ("f :: forall a. a\nf x = x", False) :
>   ("f :: forall a. a -> a\nf x = x :: a", True) :
>   ("f :: forall a. a -> (a -> a)\nf x y = y", True) :
>   ("f :: (forall a. a) -> (forall b. b -> b)\nf x y = y", True) :
>   ("f :: forall b. (forall a. a) -> (b -> b)\nf x y = y", True) :
>   ("data One where A :: Two -> One\ndata Two where B :: One -> Two", True) :
>   ("data Foo where Foo :: Foo\ndata Bar where Bar :: Bar\nf Foo = Foo\nf Bar = Foo", False) :
>   ("data Foo where Foo :: Foo\ndata Bar where Bar :: Bar\nf :: Bar -> Bar\nf Foo = Foo\nf Bar = Foo", False) :
>   ("f :: forall a (n :: Num) . n ~ n => a -> a\nf x = x", True) :
>   ("f :: forall a (n :: Num) . n ~ m => a -> a\nf x = x", False) :
>   (vecDecl ++ "vhead (Cons x xs) = x\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", False) :
>   (vecDecl ++ "vhead :: forall (n :: Num) a. Vec (1+n) a -> a\nvhead (Cons x xs) = x\nid2 :: forall (n :: Num) a. Vec n a -> Vec n a\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", True) :
>   (vecDecl ++ "append :: forall a (m n :: Num) . (0 <= m, 0 <= n, 0 <= (m + n)) => Vec m a -> Vec n a -> Vec (m+n) a\nappend Nil ys = ys\nappend (Cons x xs) ys = Cons x (append xs ys)", True) :
>   (vecDecl ++ "append :: forall a (m n :: Num) . 0 <= n => Vec m a -> Vec n a -> Vec (m+n) a\nappend Nil ys = ys\nappend (Cons x xs) ys = Cons x (append xs ys)", True) :
>   (vecDecl ++ "vtail :: forall (n :: Num) a. Vec (n+1) a -> Vec n a\nvtail (Cons x xs) = xs", True) :
>   (vecDecl ++ "lie :: forall a (n :: Num) . Vec n a\nlie = Nil", False) :
>   (vecDecl ++ "vhead :: forall a (m :: Num). 0 <= m => Vec (m+1) a -> a\nvhead (Cons x xs) = x", True) :
>   (vecDecl ++ "silly :: forall a (m :: Num). m <= -1 => Vec m a -> a\nsilly (Cons x xs) = x", True) :
>   (vecDecl ++ "silly :: forall a (m :: Num). m <= -1 => Vec m a -> a\nsilly (Cons x xs) = x\nbad = silly (Cons Nil Nil)", False) :
>   (vecDecl ++ "vhead :: forall a (m :: Num). 0 <= m => Vec (m+1) a -> a\nvhead (Cons x xs) = x\nwrong = vhead Nil", False) :
>   (vecDecl ++ "vhead :: forall a (m :: Num). 0 <= m => Vec (m+1) a -> a\nvhead (Cons x xs) = x\nright = vhead (Cons Nil Nil)", True) :
>   (vecDecl ++ "vtail :: forall a (m :: Num). 0 <= m => Vec (m+1) a -> Vec m a\nvtail (Cons x xs) = xs\ntwotails :: forall a (m :: Num). (0 <= m, 0 <= (m+1)) => Vec (m+2) a -> Vec m a \ntwotails xs = vtail (vtail xs)", True) :
>   (vecDecl ++ "vtail :: forall a (m :: Num). 0 <= m => Vec (m+1) a -> Vec m a\nvtail (Cons x xs) = xs\ntwotails xs = vtail (vtail xs)", True) :
>   (vecDecl ++ "f :: forall a (n m :: Num). n ~ m => Vec n a -> Vec m a\nf x = x", True) :
>   (vecDecl ++ "id2 :: forall a (n :: Num) . Vec n a -> Vec n a\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", True) :
>   (vecDecl ++ "id2 :: forall a (n m :: Num) . Vec n a -> Vec m a\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", False) :
>   (vecDecl ++ "id2 :: forall a (n m :: Num) . n ~ m => Vec n a -> Vec m a\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", True) :
>   (vec2Decl ++ "id2 :: forall a (n m :: Num) . n ~ m => Vec a n -> Vec a m\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", True) :
>   ("f :: forall a. 0 ~ 1 => a\nf = f", False) :
>   -- ("x = y\ny = x", True) :
>   ("f :: forall a . pi (m :: Num) . a -> a\nf {0} x = x\nf {n} x = x", True) :
>   ("f :: forall a . a -> (pi (m :: Num) . a)\nf x {m} = x", True) :
>   (vecDecl ++ "vec :: forall a . pi (m :: Num) . 0 <= m => a -> Vec m a\nvec {0} x = Nil\nvec {n+1} x = Cons x (vec {n} x)", True) :
>   (natDecl ++ "nat :: pi (n :: Num) . 0 <= n => Nat\nnat {0} = Zero\nnat{m+1} = Suc (nat {m})", True) :
>   -- ("data T :: Num -> * where C :: pi (n :: Num) . T n\nf (C {j}) = C {j}", True) :
>   -- ("data T :: Num -> * where C :: pi (n :: Num) . T n\nf :: forall (n :: Num) . T n -> T n\nf (C {i}) = C {i}", True) :
>   ("data T :: Num -> * where C :: forall (m :: Num) . pi (n :: Num) . m ~ n => T m\nf :: forall (n :: Num) . T n -> T n\nf (C {i}) = C {i}", True) :
>   -- ("data T :: Num -> * where C :: pi (n :: Num) . T n\nf :: forall (n :: Num) . T n -> T n\nf (C {0}) = C {0}\nf (C {n+1}) = C {n+1}", True) :
>   ("data T :: Num -> * where C :: forall (m :: Num) . pi (n :: Num) . m ~ n => T m\nf :: forall (n :: Num) . T n -> T n\nf (C {0}) = C {0}\nf (C {n+1}) = C {n+1}", True) :
>   ("f :: Integer -> Integer\nf x = x", True) :
>   ("f :: pi (n :: Num) . Integer\nf {n} = n", True) :
>   ("f :: pi (n :: Num) . Integer\nf {0} = 0\nf {n+1} = n", True) :
>   ("f :: pi (n :: Num) . Integer\nf {n+1} = n", True) :
>   (vecDecl ++ "vtake :: forall (n :: Num) a . pi (m :: Num) . (0 <= m, 0 <= n) => Vec (m + n) a -> Vec m a\nvtake {0}   _            = Nil\nvtake {i+1} (Cons x xs) = Cons x (vtake {i} xs)", True) :
>   (vecDecl ++ "vfold :: forall (n :: Num) a (f :: Num -> *) . f 0 -> (forall (m :: Num) . 0 <= m => a -> f m -> f (m + 1)) -> Vec n a -> f n\nvfold n c Nil         = n\nvfold n c (Cons x xs) = c x (vfold n c xs)", True) :
>   ("data One where One :: One\ndata Ex where Ex :: forall a. a -> (a -> One) -> Ex\nf (Ex s g) = g s", True) :
>   ("data One where One :: One\ndata Ex where Ex :: forall a. a -> (a -> One) -> Ex\nf :: Ex -> One\nf (Ex s g) = g s", True) :
>   ("data One where One :: One\ndata Ex where Ex :: forall a. a -> Ex\nf (Ex a) = a", False) :
>   ("data One where One :: One\ndata Ex where Ex :: forall a. a -> Ex\nf (Ex One) = One", False) :
>   ("data Ex where Ex :: pi (n :: Num) . Ex\nf (Ex {n}) = n", True) : 
>   ("data Ex where Ex :: pi (n :: Num) . Ex\ndata T :: Num -> * where T :: pi (n :: Num) . T n\nf (Ex {n}) = T {n}", False) :
>   ("data Ex where Ex :: pi (n :: Num) . Ex\ndata T :: Num -> * where T :: pi (n :: Num) . T n\nf (Ex {n+1}) = T {n}", False) : 
>   ("f = let g = \\ x -> x\n in g g", True) :
>   ("f = let x = x\n in x", True) :
>   ("f = let x = 0\n in x", True) :
>   ("f = let x = 0\n in f", True) :
>   ("f = let g x y = y\n in g f", True) :
>   ("f x = let y = x\n in y", True) :
>   ("f x = let y z = x\n          a = a\n  in y (x a)", True) :
>   ("f :: forall a. a -> a\nf x = x :: a", True) :
>   ("f :: forall b. (forall a. a -> a) -> b -> b\nf c = c\ng = f (\\ x -> x)", True) :
>   ("f :: forall b. (forall a. a -> a) -> b -> b\nf c = c\ng = f (\\ x y -> x)", False) :
>   ("f :: forall b. (forall a. a -> a) -> b -> b\nf c = c c\ng = f (\\ x -> x) (\\ x y -> y)", True) :
>   ("f :: forall b. (forall a. a -> a -> a) -> b -> b\nf c x = c x x\ng = f (\\ x y -> x)", True) :
>   (vec2Decl ++ "vfold :: forall (n :: Num) a (f :: Num -> *) . f 0 -> (forall (m :: Num) . 1 <= m => a -> f (m-1) -> f m) -> Vec a n -> f n\nvfold = vfold\nvbuild :: forall (n :: Num) a . Vec a n -> Vec a n\nvbuild = vfold Nil Cons", True) :
>   (vec2Decl ++ "vfold :: forall (n :: Num) a (f :: Num -> *) . f 0 -> (forall (m :: Num) . 1 <= m => a -> f (m-1) -> f m) -> Vec a n -> f n\nvfold = vfold\nvbuild = vfold Nil Cons", True) :
>   ("f :: forall b. (forall a . pi (m :: Num) . 0 <= m => a -> a) -> b -> b\nf h = h {0}\ng :: forall a . pi (m :: Num) . a -> a\ng {m} = \\ x -> x\ny = f g", True) :
>   ("f :: forall b. (forall a . pi (m :: Num) . (0 <= m, m <= 3) => a -> a) -> b -> b\nf h = h {0}\ng :: forall a . pi (m :: Num) . (0 <= m, m <= 3) => a -> a\ng {m} = \\ x -> x\ny = f g", True) :
>   ("f :: forall b. (forall a . pi (m :: Num) . (0 <= m, m <= 3) => a -> a) -> b -> b\nf h = h {0}\ng :: forall a . pi (m :: Num) . (m <= 3, 0 <= m) => a -> a\ng {m} = \\ x -> x\ny = f g", True) :
>   ("f :: forall (b :: Num -> *) (n :: Num) . (0 <= n, n <= 3) => (forall (a :: Num -> *) (m :: Num) . (0 <= m, m <= 3) => a m -> a m) -> b n -> b n\nf h = h\ng :: forall (a :: Num -> *) (m :: Num) . (m <= 3, 0 <= m) => a m -> a m\ng = \\ x -> x\ny = f g", True) :
>   ("f :: ((Integer -> (forall a. a -> a)) -> Integer) -> (Integer -> (forall a . a)) -> Integer\nf g h = g h", True) : 
>   ("f :: ((Integer -> (forall a. a -> a)) -> Integer) -> (Integer -> (forall a . a)) -> Integer\nf = f", True) : 
>   ("f :: (Integer -> (forall a. a -> a)) -> (forall b . (b -> b) -> (b -> b))\nf x = x 0", True) :
>   ("f :: (Integer -> Integer -> (pi (m :: Num) . forall a. a -> a)) -> Integer -> (pi (m :: Num) . forall d b . (b -> b) -> (b -> b))\nf x = x 0", True) :
>   ("f :: (forall a. a) -> (forall a. a) -> (forall a.a)\nf x y = x\ng = let loop = loop\n    in f loop", True) :
>   ("f :: (forall a. a) -> (forall a. a) -> (forall a.a)\nf x y = x\ng = let loop = loop\n    in f loop\nh :: Integer\nh = g 0", False) :
>   ("loop :: forall a. a\nloop = loop\nf :: (forall a. a) -> (forall a. a) -> (forall a.a)\nf x y = x\ng = f loop\nh :: Integer\nh = g 0", False) :
>   ("f :: (forall a. a) -> (forall a. a) -> (forall a.a)\nf x y = x\ng :: (forall x . x) -> (forall y. y -> y)\ng = let loop = loop\n    in f loop", True) :
>   ("f :: (forall a. a) -> (forall a. a) -> (forall a.a)\nf x y = x\ng :: (forall x . x -> x) -> (forall y. y)\ng = let loop = loop\n    in f loop", False) :
>   ("data High where High :: (forall a. a) -> High\nf (High x) = x", True) :
>   ("data Higher where Higher :: ((forall a. a) -> Integer) -> Higher\nf (Higher x) = x", True) :
>   ("data Higher where Higher :: ((forall a. a) -> Integer) -> Higher\nf :: Higher -> (forall a. a) -> Integer\nf (Higher x) = x", True) :
>   ("data Higher where Higher :: ((forall a. a) -> Integer) -> Higher\nf (Higher x) = x\nx = f (Higher (\\ zzz -> 0)) 0", False) :
>   ("tri :: forall a . pi (m n :: Num) . (m < n => a) -> (m ~ n => a) -> (m > n => a) -> a\ntri = tri\nf :: pi (m n :: Num) . m ~ n => Integer\nf = f\nloop = loop\ng :: pi (m n :: Num) . Integer\ng {m} {n} = tri {m} {n} loop (f {m} {n}) loop", True) :
>   ("tri :: forall a . pi (m n :: Num) . (m < n => a) -> (m ~ n => a) -> (m > n => a) -> a\ntri = undefined\ntri2 :: forall a . pi (m n :: Num) . (m < n => a) -> (m ~ n => a) -> (m > n => a) -> a\ntri2 = tri", True) :
>   ("tri :: forall a . pi (m n :: Num) . (m < n => a) -> (m ~ n => a) -> (m > n => a) -> a\ntri = tri\nf :: pi (m n :: Num) . m ~ n => Integer\nf = f\nloop = loop\ng :: pi (m n :: Num) . Integer\ng {m} {n} = tri {m} {n} loop loop (f {m} {n})", False) :
>   ("f :: forall a. pi (m n :: Num) . m ~ n => a\nf = f\nid2 x = x\ny :: forall a . pi (m n :: Num) . a\ny {m} {n} = id2 (f {m} {n})", False) :
>   ("data Eql :: Num -> Num -> * where Refl :: forall (m n :: Num) . m ~ n => Eql m n\ndata Ex :: (Num -> *) -> * where Ex :: forall (p :: Num -> *)(n :: Num) . p n -> Ex p\nf :: pi (n :: Num) . Ex (Eql n)\nf {0} = Ex Refl\nf {n+1} = Ex Refl", True) :
>   ("data Eql :: Num -> Num -> * where Refl :: forall (m n :: Num) . m ~ n => Eql m n\ndata Ex :: (Num -> *) -> * where Ex :: forall (p :: Num -> *)(n :: Num) . p n -> Ex p\nf :: pi (n :: Num) . Ex (Eql n)\nf {0} = Ex Refl\nf {n+1} = f {n}", False) :
>   ("data Eql :: Num -> Num -> * where Refl :: forall (m n :: Num) . m ~ n => Eql m n\ndata Ex :: (Num -> *) -> * where Ex :: forall (p :: Num -> *) . pi (n :: Num) . p n -> Ex p\nf :: pi (n :: Num) . Ex (Eql n)\nf {0} = Ex {0} Refl\nf {n+1} = Ex {n+1} Refl", True) :
>   ("data Eql :: Num -> Num -> * where Refl :: forall (m n :: Num) . m ~ n => Eql m n\ndata Ex :: (Num -> *) -> * where Ex :: forall (p :: Num -> *) . pi (n :: Num) . p n -> Ex p\nf :: pi (n :: Num) . Ex (Eql n)\nf {0} = Ex {0} Refl\nf {n+1} = Ex {n} Refl", False) :
>   ("data Eql :: Num -> Num -> * where Refl :: forall (m n :: Num) . m ~ n => Eql m n\ndata Ex :: (Num -> *) -> * where Ex :: forall (p :: Num -> *) . pi (n :: Num) . p n -> Ex p\nf :: pi (n :: Num) . Ex (Eql n)\nf {0} = Ex {0} Refl\nf {n+1} = f {n}", False) :
>   ("data Eql :: Num -> Num -> * where Refl :: forall (m n :: Num) . m ~ n => Eql m n\ndata Ex :: (Num -> *) -> * where Ex :: forall (p :: Num -> *) . pi (n :: Num) . p n -> Ex p\nf :: pi (n :: Num) . Ex (Eql n)\nf {0} = Ex {0} Refl\nf {n+1} = f {n-1}", False) :
>   ("tri :: forall (a :: Num -> Num -> *) . (forall (m n :: Num) . (0 <= m, m < n) => a m n) -> (forall (m   :: Num) . 0 <= m        => a m m) -> (forall (m n :: Num) . (0 <= n, n < m) => a m n) -> (pi (m n :: Num) . (0 <= m, 0 <= n) => a m n)\ntri a b c {0}   {n+1} = a\ntri a b c {0}   {0}   = b\ntri a b c {m+1} {0}   = c\ntri a b c {m+1} {n+1} = tri a b c {m} {n}", False) :
>   ("tri :: forall (a :: Num -> Num -> *) . (forall (m n :: Num) . (0 <= m, m < n) => a m n) -> (forall (m   :: Num) . 0 <= m        => a m m) -> (forall (m n :: Num) . (0 <= n, n < m) => a m n) -> (forall (m n :: Num) . (0 <= m, 0 <= n) => a m n -> a (m+1) (n+1)) -> (pi (m n :: Num) . (0 <= m, 0 <= n) => a m n)\ntri a b c step {0}   {n+1} = a\ntri a b c step {0}   {0}   = b\ntri a b c step {m+1} {0}   = c\ntri a b c step {m+1} {n+1} = step (tri a b c step {m} {n})", True) :
>   ("tri :: forall a . pi (m n :: Num) . (0 <= m, 0 <= n) => (pi (d :: Num) . (0 < d, d ~ m - n) => a) -> (n ~ m => a) -> (pi (d :: Num) . (0 < d, d ~ n - m) => a) -> a\ntri {0}   {0}   a b c = b\ntri {m+1} {0}   a b c = a {m+1}\ntri {0}   {n+1} a b c = c {n+1}\ntri {m+1} {n+1} a b c = tri {m} {n} a b c", True) :
>   ("f :: forall a . pi (m n :: Num) . a\nf {m} {n} = let h :: m ~ n => a\n                h = h\n            in f {m} {n}", True) :
>   ("f :: forall a (m n :: Num) . (m ~ n => a) -> a\nf x = x", False) :
>   ("f :: forall a (m n :: Num) . ((m ~ n => a) -> a) -> (m ~ n => a) -> a\nf x y = x y", True) :
>   ("f :: forall a (m n :: Num) . ((m ~ n => a) -> a) -> (m ~ n + 1 => a) -> a\nf x y = x y", False) :
>   ("f :: forall a . pi (m n :: Num) . a\nf {m} {n} = let h :: m ~ n => a\n                h = h\n            in h", False) :
>   ("f :: forall a . pi (m n :: Num) . ((m ~ 0 => a) -> a) -> a\nf {m} {n} x = let h :: m ~ n => a\n                  h = h\n            in x h", False) :
>   ("f :: pi (n :: Num) . Integer\nf {n} | {n >= 0} = n\nf {n} | {n < 0} = 0", True) :
>   ("f :: pi (n :: Num) . Integer\nf {n} | {m ~ 0} = n", False) : 
>   ("f :: pi (n :: Num) . Integer\nf {n} | {n > 0, n < 0} = f {n}\nf {n} | True = 0", True) :
>   ("f :: pi (n :: Num) . (n ~ 0 => Integer) -> Integer\nf {n} x | {n ~ 0} = x\nf {n} x = 0", True) : 
>   ("f :: pi (n :: Num) . (n ~ 0 => Integer) -> Integer\nf {n} x | {n ~ 0} = x\nf {n} x = x", False) : 
>   ("x = 0\nx = 1", False) : 
>   ("x :: Integer\nx = 0\nx = 1", False) : 
>   ("x = 0\ny = x\nx = 1", False) : 
>   ("x = y\ny :: Integer\ny = x", True) : 
>   ("x :: forall (a :: * -> *) . a\nx = x", False) : 
>   (vec3Decl ++ "vhead (Cons x xs) = x\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", False) :
>   (vec3Decl ++ "vhead :: forall (n :: Num) a. Vec (1+n) a -> a\nvhead (Cons x xs) = x\nid2 :: forall (n :: Num) a. Vec n a -> Vec n a\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", True) :
>   (vec3Decl ++ "append :: forall a (m n :: Num) . (0 <= m, 0 <= n, 0 <= (m + n)) => Vec m a -> Vec n a -> Vec (m+n) a\nappend Nil ys = ys\nappend (Cons x xs) ys = Cons x (append xs ys)", True) :
>   (vec3Decl ++ "append :: forall a (m n :: Num) . 0 <= n => Vec m a -> Vec n a -> Vec (m+n) a\nappend Nil ys = ys\nappend (Cons x xs) ys = Cons x (append xs ys)", True) :
>   (vec3Decl ++ "vtail :: forall (n :: Num) a. Vec (n+1) a -> Vec n a\nvtail (Cons x xs) = xs", True) :
>   (vec3Decl ++ "lie :: forall a (n :: Num) . Vec n a\nlie = Nil", False) :
>   (vec3Decl ++ "vhead :: forall a (m :: Num). 0 <= m => Vec (m+1) a -> a\nvhead (Cons x xs) = x", True) :
>   (vec3Decl ++ "silly :: forall a (m :: Num). m <= -1 => Vec m a -> a\nsilly (Cons x xs) = x", True) :
>   (vec3Decl ++ "silly :: forall a (m :: Num). m <= -1 => Vec m a -> a\nsilly (Cons x xs) = x\nbad = silly (Cons Nil Nil)", False) :
>   (vec3Decl ++ "vhead :: forall a (m :: Num). 0 <= m => Vec (m+1) a -> a\nvhead (Cons x xs) = x\nwrong = vhead Nil", False) :
>   (vec3Decl ++ "vhead :: forall a (m :: Num). 0 <= m => Vec (m+1) a -> a\nvhead (Cons x xs) = x\nright = vhead (Cons Nil Nil)", True) :
>   (vec3Decl ++ "vtail :: forall a (m :: Num). 0 <= m => Vec (m+1) a -> Vec m a\nvtail (Cons x xs) = xs\ntwotails :: forall a (m :: Num). (0 <= m, 0 <= (m+1)) => Vec (m+2) a -> Vec m a \ntwotails xs = vtail (vtail xs)", True) :
>   (vec3Decl ++ "vtail :: forall a (m :: Num). 0 <= m => Vec (m+1) a -> Vec m a\nvtail (Cons x xs) = xs\ntwotails xs = vtail (vtail xs)", True) :
>   (vec3Decl ++ "f :: forall a (n m :: Num). n ~ m => Vec n a -> Vec m a\nf x = x", True) :
>   (vec3Decl ++ "id2 :: forall a (n :: Num) . Vec n a -> Vec n a\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", True) :
>   (vec3Decl ++ "id2 :: forall a (n m :: Num) . Vec n a -> Vec m a\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", False) :
>   (vec3Decl ++ "id2 :: forall a (n m :: Num) . n ~ m => Vec n a -> Vec m a\nid2 Nil = Nil\nid2 (Cons x xs) = Cons x xs", True) :
>   (vec3Decl ++ "data Pair :: * -> * -> * where Pair :: forall a b. a -> b -> Pair a b\nvsplit2 :: forall (n :: Num) a . pi (m :: Num) . Vec (m + n) a -> Pair (Vec m a) (Vec n a)\nvsplit2 {0}   xs           = Pair Nil xs\nvsplit2 {n+1} (Cons x xs) = let  f (Pair ys zs)  = Pair (Cons x ys) zs\n                                 xs'             = vsplit2 {n} xs\n                             in f xs'", True) :
>   ("data Max :: Num -> Num -> Num -> * where\n  Less :: forall (m n :: Num) . m < n => Max m n n\n  Same :: forall (m :: Num) . Max m m m\n  More :: forall (m n :: Num) . m > n => Max m n m", True) :
>   ("data In :: Num -> * where\nint :: pi (n :: Num) . In n\nint = int\ndata Even :: Num -> * where\n  Twice :: pi (n :: Num) . Even (2 * n)\nunEven (Twice {n}) = int {n}", False) :
>   ("data In :: Num -> * where\nint :: pi (n :: Num) . In n\nint = int\ndata Even :: Num -> * where\n  Twice :: pi (n :: Num) . Even (2 * n)\nunEven :: forall (n :: Num). Even (2 * n) -> In n\nunEven (Twice {n}) = int {n}", True) :
>   ("f :: Boo -> Boo\nf x = x\ndata Boo where Boo :: Boo", True) :
>   ("data Ex where Ex :: pi (n :: Num) . Ex\nf :: forall a . (pi (n :: Num) . a) -> Ex -> a\nf g (Ex {n}) = g {n}", True) :
>   ("y = 2\ny :: Integer", True) :
>   ("y = 2\nx = 3\ny :: Integer", True) :
>   ("data UNat :: Num -> * where\ndata Bad :: (Num -> Num) -> * where Eek :: forall (f :: Num -> Num) . UNat (f 0) -> Bad f\nbadder :: forall (g :: Num -> Num -> Num) . Bad (g 1) -> UNat (g (2-1) 0)\nbadder (Eek n) = n", False) :
>   ("narg {n} = n", True) :
>   ("data UNat :: Num -> * where\nunat :: pi (n :: Num) . UNat n\nunat = unat\nnarg {n} = unat {n}", True) :
>   ("data UNat :: Num -> * where\nunat :: pi (n :: Num) . 0 <= n => UNat n\nunat = unat\nnarg {n} = unat {n}", True) :
>   ("data UNat :: Num -> * where\nunat :: pi (n :: Num) . UNat n\nunat = unat\nf :: UNat 0 -> UNat 0\nf x = x\nnarg {n} = f (unat {n})", True) :
>   ("f :: pi (m :: Nat) . Integer\nf {m} = m", True) :
>   ("bad :: forall (m n :: Num) . Integer\nbad | {m ~ n} = 0\nbad | True    = 1", False) :
>   ("worse :: forall (n :: Num) . Integer\nworse = n", False) :
>   ("f :: pi (m :: Num) . Integer\nf = f\nworse :: forall (n :: Num) . Integer\nworse = f {n}", False) :
>   ("f = \\ {x} -> x", True) :
>   ("f = \\ {x} y {z} -> x", True) :
>   ("f = \\ {x} y {z} -> x y", False) :
>   ("f = \\ {x} y {z} -> y x", True) :
>   ("f = \\ {x} y {z} -> y {x}", False) :
>   ("f :: pi (n :: Num) . Integer\nf = \\ {x} -> x", True) :
>   ("f :: forall a . pi (m :: Num) . (Integer -> a) -> a\nf = \\ {x} y -> y x", True) :
>   ("f :: forall a . pi (m :: Num) . (pi (n :: Num) . a) -> a\nf = \\ {x} y -> y {x}", True) :
>   ("f = \\ a -> a\ng = \\ {x} -> f (\\ {y} -> y) {x}", True) :
>   ("f :: (pi (n :: Num) . Integer) -> (pi (n :: Num) . Integer)\nf = \\ a -> a\ng = \\ {x} -> f (\\ {y} -> y) {x}", True) :
>   ("f :: pi (n :: Num) . forall a . a -> a\nf = \\ {n} x -> x", True) :
>   ("f g {n} = g {n}", True) :
>   ("f :: forall a. (pi (n :: Num) . a) -> (pi (n :: Num) . a)\nf g {n} = g {n}", True) :
>   ("f :: pi (n :: Num) . Integer\nf = \\ {n} -> n\ng = \\ {n} -> f {n}", True) :
>   ("f :: pi (n :: Nat) . Integer\nf = \\ {n} -> n\ng = \\ {n} -> f {n}", True) :
>   ("f :: pi (n :: Nat) . Integer\nf = \\ {n} -> n\ng :: pi (n :: Num) . Integer\ng = \\ {n} -> f {n}", False) :
>   ("f :: pi (n :: Nat) . Integer\nf = \\ {n} -> n\ng :: pi (n :: Nat) . Integer\ng = \\ {n} -> f {n}", True) :
>   ("f :: (pi (n :: Nat) . Integer) -> Integer\nf g = g {3}", True):
>   ("f :: (pi (n :: Nat) . Integer) -> Integer\nf h = h {3}\ny :: pi (n :: Nat) . Integer\ny {n} = 3\ng = f (\\ {n} -> y {n})", True):
>   ("data D :: Num -> * where\n  Zero :: D 0\n  NonZero :: forall (n :: Num) . D n\nisZ :: forall a . pi (n :: Num) . (n ~ 0 => a) -> a -> a\nisZ = isZ\nx :: pi (n :: Num) . D n\nx {n} = isZ {n} Zero Zero", False) :
>   ("data D :: Num -> * where\n  Zero :: D 0\n  NonZero :: forall (n :: Num) . D n\nisZ :: forall a . pi (n :: Num) . (n ~ 0 => a) -> a -> a\nisZ = isZ\nx :: pi (n :: Num) . D n\nx {n} = isZ {n} Zero NonZero", True) :
>   -- ("f :: forall (n :: Num) . n <= 42 => Integer\nf = f", True) :
>   ("f :: forall (t :: Num -> *)(n :: Num) . n <= 42 => t n -> Integer\nf = f\ng :: forall (s :: Num -> *) . (forall (n :: Num) . n <= 42 => s n -> Integer) -> Integer\ng = g\nh = g f", True) :
>   ("a :: forall (x :: Num) . Integer\na =\n  let f :: forall (t :: Num -> *)(n :: Num) . n <= x => t n -> Integer\n      f = f\n      g :: forall (s :: Num -> *) . (forall (n :: Num) . n <= x => s n -> Integer) -> Integer\n      g = g\n  in g f", True) :
>   ("noo :: Bool -> Bool\nnoo x = case x of\n  True -> False\n  False -> True", True) :
>   ("noo :: Bool -> Bool\nnoo x = case x of\n  True -> False\n  False -> 3", False) :
>   (vecDecl ++ "f :: forall (n :: Num) a . Vec n a -> Vec n a\nf x = case x of\n  Nil -> Nil\n  Cons x xs -> Cons x xs", True) :
>   ("noo x = case x of\n  True -> False\n  False -> True", True) :
>   ("noo x = case x of\n  True -> False\n  False -> 3", False) :
>   (vecDecl ++ "f x = case x of\n  Nil -> Nil\n  Cons x xs -> Cons x xs", False) :
>   ("f :: forall (t :: Num -> *)(m n :: Num) . t (m * n) -> t (m * n)\nf x = x", True) :
>   ("f :: forall (t :: Num -> *)(m n :: Num) . t (m * n) -> t (n * m)\nf x = x", True) :
>   ("f :: forall (t :: Num -> *)(m n :: Num) . t (m * n) -> t (m + n)\nf x = x", False) :
>   ("f :: forall (f :: Num -> *) . f (min 2 3) -> f (min 3 2)\nf x = x", True) :
>   ("f :: forall (f :: Num -> *) . f (min 2 3) -> f (min 1 2)\nf x = x", False) :
>   ("f :: forall (f :: Num -> *)(a :: Num) . f (max a 3) -> f (max a 3)\nf x = x", True) :
>   ("f :: forall (f :: Num -> *)(a :: Num) . f (max a 3) -> f (max 3 a)\nf x = x", True) :
>   ("f :: forall (f :: Num -> *)(a :: Num) . f (max a 3) -> f (max 2 a)\nf x = x", False) :
>   ("f :: forall (f :: Num -> *)(a b :: Num) . f (min a b) -> f (min b a)\nf x = x", True) :
>   ("f :: forall (f :: Num -> *)(a b c :: Num) . (a <= b, b <= c) => f (min a b) -> f (min c a)\nf x = x", True) :
>   ("f :: forall (f :: Num -> *)(a b c :: Num) . (a >= b, b <= c) => f (min a b) -> f (min c a)\nf x = x", False) :
>   ("f :: forall (f :: Num -> *)(a :: Num) . a > 99 => f a -> f (abs a)\nf x = x", True) :
>   ("f :: forall (f :: Num -> *) . f (signum (-6)) -> f (abs (-1) - 2)\nf x = x", True) :
>   ("f :: pi (m :: Num) . Integer\nf {m} = f {abs m}", True) :
>   ("f :: forall (f :: Num -> *)(a :: Num) . f (2 ^ a) -> f (2 ^ a)\nf x = x", True) :
>   ("f :: forall (f :: Num -> *)(a :: Num) . f (a ^ 2) -> f (a ^ 3)\nf x = x", False) :
>   ("f :: forall (f :: Num -> *)(a :: Num) . f (3 ^ 2) -> f 9\nf x = x", True) :
>   ("f :: forall (f :: Num -> *)(a b :: Num) . a ~ b => f (a ^ 1) -> f b\nf x = x", True) :
>   ("f :: pi (m :: Num) . Integer\nf {m} = f {6 ^ 2 + m}", True) :
>   (vec2Decl ++ "append :: forall a (m n :: Num) . Vec a m -> Vec a n -> Vec a (m+n)\nappend = append\nflat :: forall a (m n :: Num). Vec (Vec a m) n -> Vec a (m*n)\nflat Nil = Nil\nflat (Cons xs xss) = append xs (flat xss)", True) :
>   ("f :: pi (x :: Num) . Bool\nf {x} | {x > 0} = True\n      | otherwise = False", True) :
>   ("f {x} | {x > 0} = True\n      | otherwise = False", True) :
>   ("needPos :: pi (x :: Num) . x > 0 => Integer\nneedPos = needPos\nf :: pi (x :: Num) . Integer\nf {x} | {x > 0} = needPos {x}\n      | otherwise = -1", True) :
>   ("needPos :: pi (x :: Num) . x > 0 => Integer\nneedPos = needPos\nf :: pi (x :: Num) . Integer\nf {x} | {x > 0} = needPos {x}\n      | otherwise = needPos {x}", False) :
>   ("needPos :: pi (x :: Num) . x > 0 => Integer\nneedPos = needPos\nf {x} | {x > 0} = needPos {x}\n      | otherwise = -1", True) :
>   ("needPos :: pi (x :: Num) . x > 0 => Integer\nneedPos = needPos\nf {x} | {x > 0} = needPos {x}\n      | otherwise = needPos {x}", True) :
>   ("f x | (case x of True -> False\n                 False -> True\n            ) = 1\n    | otherwise = 0", True) :
>   ("f x | True = 1\n    | False = True", False) :
>   ("f :: forall (f :: Num -> *)(a b :: Num) . f ((a + 2) * b) -> f (b + b + b * a)\nf x = x", True) :
>   ("f :: forall (f :: Num -> *)(a b :: Num) . 0 <= a * b => f a -> f b\nf = f\ng :: forall (f :: Num -> *)(a b :: Num) . (0 <= a, 0 <= b) => f a -> f b\ng = f", True) :
>   ("f :: forall (f :: Num -> *)(a b :: Num) . 0 <= a * b + a => f a -> f b\nf = f\ng :: forall (f :: Num -> *)(a b :: Num) . (0 <= a, 0 <= b + 1) => f a -> f b\ng = f", True) :
>   ("f :: forall (f :: Num -> *)(a b :: Num) . 0 <= b + 1 => f a -> f b\nf = f\ng :: forall (f :: Num -> *)(a b :: Num) . (0 <= a, 0 <= a * b + a) => f a -> f b\ng = f", True) :
>   ("f :: forall (f :: Num -> *)(a :: Num) . f (a ^ (-1)) -> f (a ^ (-1))\nf x = x", False) :
>   ("f :: forall (f :: Num -> *)(a :: Num) . f (a * a ^ (-1)) -> f 1\nf x = x", False) :
>   ("data Fin :: Num -> * where\ndata Tm :: Num -> * where A :: forall (m :: Num) . 0 <= m => Tm m -> Tm m -> Tm m\nsubst :: forall (m n :: Num) . 0 <= n => (pi (w :: Num) . 0 <= w => Fin (w+m) -> Tm (w + n)) -> Tm m -> Tm n\nsubst s (A f a) = A (subst s f) (subst s a)", True) :
>   ("x = 2 + 3", True) :
>   ("x = 2 - 3", True) :
>   ("x = - 3", True) :
>   ("f :: forall (f :: Num -> *)(a b :: Num) . f (2 ^ (a + b)) -> f (2 ^ a * 2 ^ b)\nf x = x", True) :
>   ("f :: forall (f :: Num -> *)(a b :: Num) . f (2 ^ (2 * a)) -> f ((2 ^ a) ^ 2)\nf x = x", True) :
>   ("f :: forall (f :: (Num -> Num) -> *) . f (min 2) -> f (min 2)\nf x = x", True) :
>   ("f :: forall (f :: Num -> *)(a :: Num) . a ~ 0 => f (0 ^ a) -> f 1\nf x = x", True) :
>   ("f :: forall (f :: * -> Num)(g :: Num -> *) . g (f Integer) -> g (f Integer)\nf x = x", True) :
>   ("f :: forall (f :: Num -> Num -> Num -> Num)(g :: Num -> *) . g (f 1 2 3) -> g (f 1 2 2)\nf x = x", False) :
>   ("f :: Integer", False) :
>   ("x :: forall a . [a]\nx = []", True) :
>   ("y :: [Integer]\ny = 1 : 2 : [3, 4]", True) :
>   ("x = [[]]", True) :
>   ("x = 'a' : [] : []", False) :
>   ("x = 1 + 3 : [6]", True) : 
>   ("x :: ()\nx = ()", True) : 
>   ("x :: (Integer, Integer)\nx = ()", False) : 
>   ("x = ((), ())", True) :
>   ("f () = ()\ng (x, y) = (y, x)", True) : 
>   ("f () = ()\nf (x, y) = (y, x)", False) : 
>   ("f xs = case xs of\n      [] -> []\n      y:ys -> y : f ys", True) :
>   ("scanl'            :: (a -> b -> a) -> a -> [b] -> [a]\nscanl' f q xs     =  q : (case xs of\n                            []   -> []\n                            x:ys -> scanl' f (f q x) ys\n                        )", True) :
>   ("a = \"hello\"", True) :
>   ("b w = w : 'o' : 'r' : ['l', 'd']", True) :
>   ("x = y\n  where y = 3", True) :
>   ("f x | z = 3\n   | otherwise = 2\n  where z = x", True) :
>   ("f = case True of True -> 3", True) :
>   ("f :: Integer\nf = case True of True -> 3", True) :
>   ("x :: Bool\nx = (<) 2 3", True) :
>   ("data Empty where", True) :
>   ("(&&&) :: Bool -> Bool -> Bool\nTrue &&& x = x\nFalse &&& _ = False", True) :
>   (vecDecl ++ "vsplit :: forall (n :: Nat) a . pi (m :: Nat) . Vec (m + n) a -> (Vec m a, Vec n a)\nvsplit {0}   xs           = (Nil, xs)\nvsplit {m+1} (Cons x xs) = case vsplit {m} xs of\n                                (ys, zs) -> (Cons x ys, zs)", True) :
>   (vecDecl ++ "vsplit :: forall (n :: Nat) a . pi (m :: Nat) . Vec (m + n) a -> (Vec m a, Vec n a)\nvsplit {0}   xs           = (Nil, xs)\nvsplit {m+1} (Cons x xs) = case vsplit {m} xs of\n                                (ys, zs) | True -> (Cons x ys, zs)", True) :
>   (vecDecl ++ "foo :: forall a (n m :: Nat) . Vec (m + n) a -> Vec (n + m) a\nfoo = foo", True) :
>   (vecDecl ++ "foo :: forall a (n m :: Nat) . Vec (m + n) a -> Vec (n + m) a\nfoo x = x\ngoo = foo", True) :
>   (vecDecl ++ "foo :: forall a (n m :: Nat) . Vec (m + n) a -> Vec (n + m) a\nfoo x = x\ngoo :: forall a (n m :: Nat) . Vec (m + n) a -> Vec (n + m) a\ngoo = foo", True) :
>   (vecDecl ++ "foo :: forall a (n m :: Nat) . Vec (m + n) a -> Vec (n + m) a\nfoo x = x\ngoo :: forall a (i :: Integer)(n :: Nat) . 0 <= i - n => Vec i a -> Vec i a\ngoo = foo", True) :
>   ("foo :: forall (f :: Num -> Num -> Num) a (p :: Num -> *) . (forall (m n :: Num) a . p m -> p n -> (f m n ~ f n m => a) -> a) -> (f 1 3 ~ f 3 1 => a) -> a\nfoo comm x = comm (undefined :: p 1) (undefined :: p 3) x", True) :
>   ("f :: forall (p :: Constraint -> *)(c :: Constraint) . c => p c -> Integer\nf = f", True) :
>   ("f :: forall (p :: Constraint -> *) . p (2 + 3 <= 7)\nf = f", True) :
>   ("class S a where\n  s :: a -> [Char]\nx = s", True) :
>   ("class T a (b :: Integer) where\n  s :: forall (p :: Integer -> *) . a -> p b -> Integer\nx = s", True) :
>   ("class S a where\n  s :: 6", False) :
>   ("f :: forall (p :: Integer -> *) . pi (x :: Integer) . p x\nf {y} = undefined :: p y", True) : 
>   ("f :: forall (p :: Integer -> *) . pi (x :: Integer) . p x\nf {y} = undefined :: p x", False) : 
>   ("f :: Show a => a -> [Char]\nf x = show x\nz :: [Char]\nz = show (3 :: Integer)", True) :
>   ("f :: Show a => a -> [Char]\nf x = show x\nz :: [Char]\nz = show 3", True) :
>   ("class Foo a where\n foo :: b -> a", True) :
>   (vecDecl ++ "class N a where n :: pi (x :: Nat) . a -> Vec x a\ninstance N Char where n {0} c = Nil", True) :
>   ("class X a where x :: a\ninstance X Integer where x = 3", True) : 
>   ("class X a where x :: a\ninstance X Integer where x = 'a'", False) : 
>   ("class X a where x :: a\ninstance X Integer where x = 3\ny :: Integer\ny = x", True) : 
>   ("class Comm (f :: Integer -> Integer -> Integer) where comm :: forall (m n :: Integer) a . (f m n ~ f n m => a) -> a\ninstance Comm (+) where comm x = x", True) :
>   ("class X a where x :: a\ninstance X a => X [a] where x = [x]", True) : 
>   ("class X a where x :: a\ninstance (X Integer, X a) => X [a] where x = [x]", True) : 
>   ("class X a where x :: a\ninstance X a => X [a] where x = []\ny :: X a => [a]\ny = x", True) : 
>   ("class (a ~ b) => X (a :: Integer) (b :: Integer) where coe :: forall (p :: Integer -> *) . p a -> p b\ninstance X a a where coe x = x", True) : 
>   ("class X a where x :: a\nclass (X a) => Y a\ny :: Y a => a\ny = x", True) : 
>   ("elimNat :: forall a . pi (n :: Nat) . (n ~ 0 => a) -> (pi (m :: Nat) . n ~ m + 1 => a) -> a\nelimNat {0}   z s = z\nelimNat {m+1} z s = s {m}\nnatToInt p {n} = elimNat {n} 0 (\\ {m} -> p m 1)", True) :
>   ("data Foo :: * -> * where\n  X :: forall a. Foo a\n  deriving Show\nf :: Foo a -> [Char]\nf = show", True) :
>   ("data Foo where\n  X :: Foo\n  deriving Show\nf :: Foo -> [Char]\nf = show", True) :
>   ("f :: Show a => b -> [Char]\nf = show", False) :
>   ("f :: Eq a => (a,a) -> (a,a) -> Bool\nf = (==)", True) :
>   ("badexp :: (Num a, Num b, Eq b, Ord b, Integral b) => a -> b -> a\nbadexp x n | (>) n 0 = f x ((-) n 1) x where\n  f :: forall _s _s' . (Num _s, Integral _s', Num _s', Eq _s') => _s -> (_s' -> (_s -> _s))\n  f _ 0 y = y\n  f x n y = g x n where\n    g x n | even n = g ((*) x x) (quot n 2)\n           | otherwise = f x ((-) n 1) ((*) x y)", False) :
>   ("type Strung = [Char]\nx = [] :: Strung", True) :
>   ("type F (a :: *) (b :: * -> *) = b a\nfoo :: a -> F a []\nfoo = return", True) :
>   (vecDecl ++ "type Suc (n :: Integer) = n + 1\ntype Vect a (n :: Integer) = Vec n a\ncons :: forall a (n :: Nat) . a -> Vect a n -> Vect a (Suc n)\ncons = Cons", True) :
>   ("type One = 1\nf :: forall (p :: Integer -> *) (n :: Integer) . n ~ One => p n -> p 1\nf x = x", True) :
>   ("type A = Integer\ntype B = A\nf :: B -> Integer\nf x = x", True) :
>   (vecDecl ++ "instance Show (Vec 0 a) where\n  show Nil = \"Nil\"", True) :
>   (vecDecl ++ "instance (0 ~ 1) => Show (Vec 0 a) where\n  show Nil = \"Nil\"", True) :
>   (vec2Decl ++ "class Nummy (n :: Integer) where num :: (pi (m :: Integer) . m ~ n => a) -> a\ninstance Nummy 0 where num f = f {0}\nclass Applicative (f :: * -> *) where\n  pure :: a -> f a\n  (<*>) :: f (a -> b) -> f a -> f b\ninstance (Nummy n, n > 0) => Applicative (Vec n) where", True) :
>   []

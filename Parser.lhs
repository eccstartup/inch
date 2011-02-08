> module Parser where

> import Control.Applicative
> import Control.Monad
> import Data.Char

> import Text.ParserCombinators.Parsec hiding (many, (<|>))
> import Text.ParserCombinators.Parsec.Expr
> import Text.ParserCombinators.Parsec.Language
> import qualified Text.ParserCombinators.Parsec.Token as T
> import qualified Text.ParserCombinators.Parsec.IndentParser as I
> import qualified Text.ParserCombinators.Parsec.IndentParser.Token as IT


> import Syntax


> instance Applicative (GenParser s a) where
>    pure  = return
>    (<*>) = ap

> instance Alternative (GenParser s a) where
>    empty = mzero
>    (<|>) = mplus

> toyDef = haskellDef

> lexer       = T.makeTokenParser toyDef    
      
> identifier     = IT.identifier lexer
> reserved       = IT.reserved lexer
> operator       = IT.operator lexer
> reservedOp     = IT.reservedOp lexer
> charLiteral    = IT.charLiteral lexer
> stringLiteral  = IT.stringLiteral lexer
> natural        = IT.natural lexer
> integer        = IT.integer lexer
> symbol         = IT.symbol lexer
> lexeme         = IT.lexeme lexer
> whiteSpace     = IT.whiteSpace lexer
> parens         = IT.parens lexer
> braces         = IT.braces lexer
> angles         = IT.angles lexer
> brackets       = IT.brackets lexer
> semi           = IT.semi lexer
> comma          = IT.comma lexer
> colon          = IT.colon lexer
> dot            = IT.dot lexer
> semiSep        = IT.semiSep lexer
> semiSep1       = IT.semiSep1 lexer
> commaSep       = IT.commaSep lexer
> commaSep1      = IT.commaSep1 lexer
 


> doubleColon = reservedOp "::"



Kinds

> kind       = kindBit `chainr1` kindArrow
> kindBit    = setKind <|> natKind
> setKind    = symbol "*" >> return Set
> natKind    = symbol "Nat" >> return KindNat
> kindArrow  = reservedOp "->" >> return KindArr



Types

> tyVarOrCon = f <$> (identifier <?> "type variable or constructor")
>   where f s  | isVar s    = TyVar s
>              | otherwise  = TyCon s

> tyVarName  = identLike True "type variable"
> tyConName  = identLike False "type constructor"
> tyVar      = TyVar <$> tyVarName
> tyCon      = TyCon <$> tyConName
> tyExp      = tyAll <|> tyPi <|> tyExpArr
> tyAll      = tyQuant "forall" (Bind All)
> tyPi       = tyQuant "pi" (Bind Pi)
> tyExpArr   = tyBit `chainr1` tyArrow
> tyBit      = tyBob `chainr1` pure TyApp
> tyBob      = tyVarOrCon <|> parens (reservedOp "->" *> pure Arr <|> tyExp)
> tyArrow    = reservedOp "->" >> return (-->)

> tyQuant q f = do
>     reserved q
>     aks <- many1 $ foo <$> quantifiedVar
>     reservedOp "."
>     t <- tyExp
>     return $ foldr (\ (a, k) t -> f a k (bind a t)) t $ join aks
>   where
>     foo :: ([as], k) -> [(as, k)]
>     foo (as, k) = map (\ a -> (a, k)) as

> quantifiedVar  =    parens ((,) <$> many1 tyVarName <* doubleColon <*> kind)
>                <|>  (\ a -> ([a] , Set)) <$> tyVarName



Terms

> expr  =    lambda
>       <|>  fexp 

> fexp = do
>     t <- foldl1 TmApp <$> many1 aexp
>     mty <- optionMaybe (doubleColon >> tyExp)
>     case mty of
>         Just ty -> return $ t :? ty
>         Nothing -> return t

> aexp  =    varOrCon
>       <|>  parens expr


> isVar :: String -> Bool
> isVar = isLower . head

> identLike var desc = try $ do
>     s <- identifier <?> desc
>     when (var /= isVar s) $ fail $ "expected " ++ desc
>     return s

> variable = identLike True "variable"

> varOrCon = f <$> (identifier <?> "term variable or constructor")
>   where f s  | isVar s    = TmVar s
>              | otherwise  = TmCon s

> dataConName  = identLike False "data constructor"

> lambda = do
>     reservedOp "\\"
>     ss <- many1 variable
>     reservedOp "->"
>     t <- fexp
>     return $ wrapLam ss t

> wrapLam :: [String] -> Tm String -> Tm String
> wrapLam [] t = t
> wrapLam (s:ss) t = lam s $ wrapLam ss t

> lam :: String -> Tm String -> Tm String
> lam s = Lam s . bind s


Programs

> program = whiteSpace >> many decl <* eof

> decl  =    DD <$> dataDecl
>       <|>  FD <$> funDecl


> dataDecl = I.lineFold $ do
>     try (reserved "data")
>     s <- tyConName
>     k <- (doubleColon >> kind) <|> return Set
>     reserved "where"
>     cs <- many $ I.lineFold constructor
>     return $ DataDecl s k cs
>     



> constructor = do
>     s <- dataConName
>     doubleColon
>     t <- tyExp
>     return (Con s t)



> funDecl = do
>     (s, p) <- patternStart
>     ps <- many $ patternFor s
>     return $ FunDecl s Nothing (p:ps)

> patternStart = I.lineFold $ (,) <$> variable <*> pattern

> patternFor s = I.lineFold $ do
>     try $ do  x <- variable
>               unless (s == x) $ fail $ "expected pattern for " ++ show s
>     pattern

> pattern = Pat <$> many patTerm <* reservedOp "=" <*> pure Trivial <*> expr

> patTerm  =    parens (PatCon <$> dataConName <*> many patTerm)
>          <|>  PatCon <$> dataConName <*> pure []
>          <|>  PatVar <$> variable
>          


> signature = do
>     s <- variable
>     doubleColon
>     t <- tyExp
>     return (s, t)
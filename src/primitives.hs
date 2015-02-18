module Primitives(primitives, ioPrimitives, eval, evalLine) where
import Types
import Parser
import Variables
import Macro
import System.IO
import Data.Array
import Data.Maybe
import Control.Monad
import Control.Monad.Except

-- | a list of all regular primitives
primitives :: [(String, [LispVal] -> ThrowsError LispVal, String)]
primitives = [("+", numericPlusop (+), "add two values"),
              ("-", numericMinop (-), "subtract two values/negate value"),
              ("*", numericBinop (*), "multiply two values"),
              ("/", numericBinop div, "divide two values"),
              ("mod", numericBinop mod, "modulo of two values"),
              ("quotient", numericBinop quot, "quotient of two values"),
              ("remainder", numericBinop rem, "remainder of two values"),
              ("round", numRound round, "rounds a number"),
              ("floor", numRound floor, "floors a number"),
              ("ceil", numRound ceiling, "ceils a number"),
              ("truncate", numRound truncate, "truncates a number"),
              ("log", numLog, "logarithm function"),
              ("sin", numOp sin, "sine function"),
              ("cos", numOp cos, "cosine function"),
              ("tan", numOp tan, "tangens function"),
              ("asin", numOp asin, "asine function"),
              ("acos", numOp acos, "acosine function"),
              ("atan", numOp atan, "atangens function"),
              ("=", numBoolBinop (==), "compare equality of two values"),
              ("<", numBoolBinop (<), "compare equality of two values"),
              (">", numBoolBinop (>), "compare equality of two values"),
              ("/=", numBoolBinop (/=), "compare equality of two values"),
              (">=", numBoolBinop (>=), "compare equality of two values"),
              ("<=", numBoolBinop (<=), "compare equality of two values"),
              ("&&", boolMulop (&&), "and operation"),
              ("||", boolMulop (||), "or operation"),
              ("string=?", strBoolBinop (==), "compare equality of two strings"),
              ("string>?", strBoolBinop (>), "compare equality of two strings"),
              ("string<?", strBoolBinop (<), "compare equality of two strings"),
              ("string<=?", strBoolBinop (<=), "compare equality of two strings"),
              ("string>=?", strBoolBinop (>=), "compare equality of two strings"),
              ("newline", printNewline, "print a newline"),
              ("car", car, "take head of list"),
              ("cdr", cdr, "take tail of list"),
              ("cons", cons, "construct list"),
              ("eq?", eqv, "check equality"),
              ("eqv?", eqv, "check equality"),
              ("equal?", equal, "check equality"),
              
              ("pair?", isDottedList, "check whether variable is a pair"),
              ("procedure?", isProcedure, "check whether variable is a procedure"),
              ("number?", isNumber, "check whether variable is a number"),
              ("integer?", isInteger, "check whether variable is an integer"),
              ("real?", isReal, "check whether variable is a real number"),
              ("list?", unaryOp isList, "check whether variable is list"),
              ("null?", isNull, "check whether variable is null"),
              ("symbol?", isSymbol, "check whether variable is symbol"),
              ("vector?", unaryOp isVector, "check whether variable is vector"),
              ("string?", isString, "check whether variable is string"),
              ("char?", isChar, "check whether vairable is char"),
              ("boolean?", isBoolean, "check whether variable is boolean"),
              ("vector", buildVector, "build a new vector"),
              ("vector-length", vectorLength, "get length of vector"),
              ("string-length", stringLength, "get length of string"),
              ("make-string", makeString, "make a new string"),
              ("make-vector", makeVector, "create a vector"),
              ("vector->list", vectorToList, "makes list from vector"),
              ("list->vector", listToVector, "makes vector from list"),
              ("symbol->string", symbol2String, "makes string from symbol"),
              ("string->symbol", string2Symbol, "makes symbol from string"),
              ("string->number", stringToNumber, "makes number from string"),
              ("string->list", stringToList, "makes list from string"),
              ("string-copy", stringCopy, "copy string"),
              ("substring", substring, "makes substring from string"),
              ("vector-ref", vectorRef, "get element from vector"),
              ("string-append", stringAppend, "append to string")]

-- | a list of all io-bound primitives
ioPrimitives :: [(String, [LispVal] -> IOThrowsError LispVal, String)]
ioPrimitives = [("apply", applyProc, "apply function"),
                ("open-input-file", makePort ReadMode, "open a file for reading"),
                ("open-output-file", makePort WriteMode, "open a file for writing"),
                ("close-input-file", closePort, "close a file opened for reading"),
                ("close-output-file", closePort, "close a file opened for writing"),
                ("read", readProc, "read from file"),
                ("write", writeProc, "write to file"),
                ("read-contents", readContents, "read contents of file"),
                ("read-all", readAll, "read and parse file")]

numericBinop :: (LispNum -> LispNum -> LispNum) -> [LispVal] -> ThrowsError LispVal
numericBinop _ singleVal@[_] = throwError $ NumArgs 2 singleVal
numericBinop op p = liftM (Number . foldl1 op) (mapM unpackNum p)

numericMinop :: (LispNum -> LispNum -> LispNum) -> [LispVal] -> ThrowsError LispVal
numericMinop _ [Number l] = return $ Number $ negate l
numericMinop op p = liftM (Number . foldl1 op) (mapM unpackNum p)

numericPlusop :: (LispNum -> LispNum -> LispNum) -> [LispVal] -> ThrowsError LispVal
numericPlusop _ [Number l] = if l > 0 then return $ Number l
                                      else return $ Number $ negate l
numericPlusop op p = liftM (Number . foldl1 op) (mapM unpackNum p)

boolBinop :: (LispVal -> ThrowsError a) -> (a -> a -> Bool) -> [LispVal] -> ThrowsError LispVal
boolBinop unpacker op args = if length args /= 2
                             then throwError $ NumArgs 2 args
                             else do left <- unpacker $ head args
                                     right <- unpacker $ args !! 1
                                     return $ Bool $ left `op` right

boolMulop :: (Bool -> Bool -> Bool) -> [LispVal] -> ThrowsError LispVal
boolMulop op p = liftM (Bool . foldl1 op) (mapM unpackBool p)

numBoolBinop :: (LispNum -> LispNum -> Bool) -> [LispVal] -> ThrowsError LispVal
numBoolBinop = boolBinop unpackNum

strBoolBinop :: (String -> String -> Bool) -> [LispVal] -> ThrowsError LispVal
strBoolBinop = boolBinop unpackStr

unaryOp :: (LispVal -> ThrowsError LispVal) -> [LispVal] -> ThrowsError LispVal
unaryOp f [v] = f v
unaryOp _ _ = throwError $ InternalError "Internal error in unaryOp"

unpackNum :: LispVal -> ThrowsError LispNum
unpackNum (Number n) = return n
unpackNum notNum = throwError $ TypeMismatch "number" notNum

unpackStr :: LispVal -> ThrowsError String
unpackStr (String s) = return s
unpackStr notString = throwError $ TypeMismatch "string" notString

unpackBool :: LispVal -> ThrowsError Bool
unpackBool (Bool b) = return b
unpackBool notBool = throwError $ TypeMismatch "boolean" notBool

numRound :: (Double -> Integer) -> [LispVal] -> ThrowsError LispVal
numRound _ [n@(Number (NumI _))] = return n
numRound op [(Number (NumF n))] = return $ Number $ NumI $ fromInteger $ op n
numRound _ [x] = throwError $ TypeMismatch "number" x
numRound _ badArgList = throwError $ NumArgs 1 badArgList

numOp :: (Double -> Double) -> [LispVal] -> ThrowsError LispVal
numOp op [(Number (NumI n))] = return $ Number $ NumF $ op $ fromInteger n
numOp op [(Number (NumF n))] = return $ Number $ NumF $ op n
numOp _ [x] = throwError $ TypeMismatch "number" x
numOp _ badArgList = throwError $ NumArgs 1 badArgList

numLog :: [LispVal] -> ThrowsError LispVal
numLog [(Number (NumI n))] = return $ Number $ NumF $ log $ fromInteger n
numLog [(Number (NumF n))] = return $ Number $ NumF $ log n
numLog [Number (NumI n), Number (NumI base)] = 
    return $ Number $ NumF $ logBase (fromInteger base) (fromInteger n)
numLog [Number (NumF n), Number (NumI base)] = 
    return $ Number $ NumF $ logBase (fromInteger base) n
numLog [x] = throwError $ TypeMismatch "number" x
numLog badArgList = throwError $ NumArgs 1 badArgList

printNewline :: [LispVal] -> ThrowsError LispVal
printNewline [] = return $ String $ unlines [""]
printNewline [badArg] = throwError $ TypeMismatch "nothing" badArg
printNewline badArgList = throwError $ NumArgs 1 badArgList

car :: [LispVal] -> ThrowsError LispVal
car [List (x : _)] = return x
car [DottedList (x : _) _] = return x
car [badArg] = throwError $ TypeMismatch "pair" badArg
car badArgList = throwError $ NumArgs 1 badArgList

cdr :: [LispVal] -> ThrowsError LispVal
cdr [List (_ : xs)] = return $ List xs
cdr [DottedList (_ : xs) x] = return $ DottedList xs x
cdr [badArg] = throwError $ TypeMismatch "pair" badArg
cdr badArgList = throwError $ NumArgs 1 badArgList

cons :: [LispVal] -> ThrowsError LispVal
cons [x, List []] = return $ List [x]
cons [x, List xs] = return $ List $ x : xs
cons [x, DottedList xs xlast] = return $ DottedList (x : xs) xlast
cons [x, y] = return $ DottedList [x] y
cons badArgList = throwError $ NumArgs 2 badArgList

eqv :: [LispVal] -> ThrowsError LispVal
eqv [Bool arg1, Bool arg2] = return $ Bool $ arg1 == arg2
eqv [Number arg1, Number arg2] = return $ Bool $ arg1 == arg2
eqv [String arg1, String arg2] = return $ Bool $ arg1 == arg2
eqv [Atom arg1, Atom arg2] = return $ Bool $ arg1 == arg2
eqv [DottedList xs x, DottedList ys y] = eqv [List $ xs ++ [x], List $ ys ++ [y]]
eqv [List arg1, List arg2] = return $ Bool $ (length arg1 == length arg2) &&
                                  and (zipWith (curry eqvPair) arg1 arg2)
                                  where eqvPair (x, y) = case eqv[x, y] of
                                                            Left _ -> False
                                                            Right (Bool val) -> val
                                                            _ -> False
eqv [_, _] = return $ Bool False
eqv badArgList = throwError $ NumArgs 2 badArgList

eqvList :: ([LispVal] -> ThrowsError LispVal) -> [LispVal] -> ThrowsError LispVal
eqvList eqvFunc [(List arg1), (List arg2)] =
        return $ Bool $ (length arg1 == length arg2) && all eqvPair (zip arg1 arg2)
    where eqvPair (x1, x2) = case eqvFunc [x1, x2] of
                                Left _           -> False
                                Right (Bool val) -> val
                                _                -> False
eqvList _ _ = throwError $ InternalError "Unexpected error in eqvList"

unpackEquals :: LispVal -> LispVal -> Unpacker -> ThrowsError Bool
unpackEquals x y (AnyUnpacker unpacker) =
        do unpacked1 <- unpacker x
           unpacked2 <- unpacker y
           return $ unpacked1 == unpacked2
        `catchError` const (return False)

equal :: [LispVal] ->ThrowsError LispVal
equal [lx@(List _), ly@(List _)] = eqvList equal [lx, ly]
equal [(DottedList xs x), (DottedList ys y)] = equal [List $ xs ++ [x], List $ ys ++ [y]]
equal [x, y] = do 
           primitiveEquals <- liftM or $ mapM (unpackEquals x y)
                              [AnyUnpacker unpackNum, AnyUnpacker unpackStr, 
                               AnyUnpacker unpackBool]
           eqvEquals <- eqv [x, y]
           return $ Bool (primitiveEquals || let (Bool z) = eqvEquals in z)
equal badArgList = throwError $ NumArgs 2 badArgList

makeVector, buildVector, vectorLength, vectorRef, vectorToList, listToVector :: [LispVal] -> ThrowsError LispVal
makeVector [(Number n)] = makeVector [Number n, List []]
makeVector [(Number (NumI n)), a] = do
    let l = replicate (fromInteger n) a
    return $ Vector $ (listArray (0, length l - 1)) l
makeVector [badType] = throwError $ TypeMismatch "integer" badType
makeVector badArgList = throwError $ NumArgs 1 badArgList

buildVector (o:os) = do
    let l = o:os
    return $ Vector $ (listArray (0, length l - 1)) l
buildVector badArgList = throwError $ NumArgs 1 badArgList

vectorLength [(Vector v)] = return $ Number $ NumI $ toInteger $ length (elems v)
vectorLength [badType] = throwError $ TypeMismatch "vector" badType
vectorLength badArgList = throwError $ NumArgs 1 badArgList

vectorRef [(Vector v), (Number (NumI n))] = return $ v ! (fromInteger n)
vectorRef [badType] = throwError $ TypeMismatch "vector integer" badType
vectorRef badArgList = throwError $ NumArgs 2 badArgList

vectorToList [(Vector v)] = return $ List $ elems v
vectorToList [badType] = throwError $ TypeMismatch "vector" badType
vectorToList badArgList = throwError $ NumArgs 1 badArgList

listToVector [(List l)] = return $ Vector $ (listArray (0, length l - 1)) l
listToVector [badType] = throwError $ TypeMismatch "list" badType
listToVector badArgList = throwError $ NumArgs 1 badArgList

makeString :: [LispVal] -> ThrowsError LispVal
makeString [(Number n)] = return $ _makeString n ' ' ""
    where _makeString count chr s =
            if count == 0
                then String s
                else _makeString (count - 1) chr (s ++ [chr])
makeString badArgList = throwError $ NumArgs 1 badArgList

stringLength :: [LispVal] -> ThrowsError LispVal
stringLength [String s] = return $ Number $ foldr (const (+1)) 0 s
stringLength [badType] = throwError $ TypeMismatch "string" badType
stringLength badArgList = throwError $ NumArgs 1 badArgList

substring :: [LispVal] -> ThrowsError LispVal
substring [(String s), (Number (NumI start)), (Number (NumI end))] = do 
    let len = fromInteger $ end - start
    let begin = fromInteger start
    return $ String $ (take len . drop begin) s
substring [badType] = throwError $ TypeMismatch "string integer integer" badType
substring badArgList = throwError $ NumArgs 3 badArgList

stringAppend :: [LispVal] -> ThrowsError LispVal
stringAppend [(String s)] = return $ String s
stringAppend (String st:sts) = do
    rest <- stringAppend sts
    case rest of
        String s -> return $ String $ st ++ s
        elsewise -> throwError $ TypeMismatch "string" elsewise
stringAppend [badType] = throwError $ TypeMismatch "string" badType
stringAppend badArgList = throwError $ NumArgs 1 badArgList

stringToNumber :: [LispVal] -> ThrowsError LispVal
stringToNumber [(String s)] = return $ Number $ NumI $ read s
stringToNumber [badType] = throwError $ TypeMismatch "string" badType
stringToNumber badArgList = throwError $ NumArgs 1 badArgList

stringToList :: [LispVal] -> ThrowsError LispVal
stringToList [(String s)] = return $ List $ map (Character) s
stringToList [badType] = throwError $ TypeMismatch "string" badType
stringToList badArgList = throwError $ NumArgs 1 badArgList

stringCopy :: [LispVal] -> ThrowsError LispVal
stringCopy [String s] = return $ String s
stringCopy [badType] = throwError $ TypeMismatch "string" badType
stringCopy badArgList = throwError $ NumArgs 2 badArgList

isNumber :: [LispVal] -> ThrowsError LispVal
isNumber ([Number _]) = return $ Bool True
isNumber _ = return $ Bool False

isReal :: [LispVal] -> ThrowsError LispVal
isReal ([Number _]) = return $ Bool True
isReal _ = return $ Bool False

isInteger :: [LispVal] -> ThrowsError LispVal
isInteger ([Number (NumI _)]) = return $ Bool True
isInteger _ = return $ Bool False

isDottedList :: [LispVal] -> ThrowsError LispVal
isDottedList ([DottedList _ _]) = return $ Bool True
isDottedList _ = return $ Bool False

isProcedure :: [LispVal] -> ThrowsError LispVal
isProcedure ([PrimitiveFunc _]) = return $ Bool True
isProcedure ([Func _]) = return $ Bool True
isProcedure ([IOFunc _]) = return $ Bool True
isProcedure _ = return $ Bool False

isVector, isList :: LispVal -> ThrowsError LispVal
isVector (Vector _) = return $ Bool True
isVector _ = return $ Bool False
isList (List _) = return $ Bool True
isList _ = return $ Bool False

isNull :: [LispVal] -> ThrowsError LispVal
isNull ([List []]) = return $ Bool True
isNull _ = return $ Bool False

isSymbol :: [LispVal] -> ThrowsError LispVal
isSymbol ([Atom _]) = return $ Bool True
isSymbol _ = return $ Bool False

symbol2String :: [LispVal] -> ThrowsError LispVal
symbol2String ([Atom a]) = return $ String a
symbol2String [notAtom] = throwError $ TypeMismatch "symbol" notAtom
symbol2String [] = return $ Bool False
symbol2String _ = return $ Bool False

string2Symbol :: [LispVal] -> ThrowsError LispVal
string2Symbol [] = return $ Bool False
string2Symbol ([String s]) = return $ Atom s
string2Symbol [notString] = throwError $ TypeMismatch "string" notString
string2Symbol args@(_ : _) = throwError $ NumArgs 1 args

isString :: [LispVal] -> ThrowsError LispVal
isString ([String _]) = return $ Bool True
isString _ = return $ Bool False

isChar :: [LispVal] -> ThrowsError LispVal
isChar ([Character _]) = return $ Bool True
isChar _ = return $ Bool False

isBoolean :: [LispVal] -> ThrowsError LispVal
isBoolean ([Bool _]) = return $ Bool True
isBoolean _ = return $ Bool False

-- | evaluates a parsed line
evalLine :: Env -> String -> IO String
evalLine env expr = runIOThrows $ liftM show $ 
                    liftThrows (readExpr expr) >>= macroEval env >>= eval env

-- | evaluates a parsed expression
eval :: Env -> LispVal -> IOThrowsError LispVal
eval _ val@(Nil _) = return val
eval _ val@(String _) = return val
eval _ val@(Number _) = return val
eval _ val@(Bool _) = return val
eval _ val@(Character _) = return val
eval _ (List [Atom "quote", val]) = return val
eval env (List [Atom "if", p, conseq, alt]) = do result <- eval env p
                                                 case result of
                                                    Bool False -> eval env alt
                                                    _          -> eval env conseq
eval env (List [Atom "if", predicate, conseq]) = do result <- eval env predicate
                                                    case result of
                                                        Bool True -> eval env conseq
                                                        _         -> eval env $ List []
eval env (List [Atom "set!", Atom var, form]) = eval env form >>= setVar env var
eval env (List [Atom "define", Atom var, form]) = eval env form >>= defineVar env var
eval env (List (Atom "define" : List (Atom var : p) : b)) = 
                            makeNormalFunc env p b >>= defineVar env var
eval env (List (Atom "define" : DottedList (Atom var : p) varargs : b)) =
                            makeVarargs varargs env p b >>= defineVar env var
eval env (List (Atom "lambda" : List p : b)) = 
                            makeNormalFunc env p b
eval env (List (Atom "lambda" : DottedList p varargs : b)) = 
                            makeVarargs varargs env p b
eval env (List (Atom "lambda" : varargs@(Atom _) : b)) = 
                            makeVarargs varargs env [] b
eval env (List [Atom "load", String filename]) =
                            load filename >>= liftM last . mapM (parse env)
                            where parse en val = macroEval env val >>= eval en
eval env (List [Atom "display", String val]) = eval env $ String val
eval env (List [Atom "display", List (function : args)]) = eval env $ List (function : args)
eval env (List [Atom "display", List val]) = eval env  $ List val
eval env (List [Atom "display", Atom val]) = eval env $ Atom val
eval _ (List [Atom "display", DottedList beginning end]) = return $ String $ showVal $ DottedList beginning end
eval _ (List [Atom "display", Number val]) = return $ String $ showVal $ Number val
eval _ (List [Atom "help", String val]) =
        return $ String $ concat $ 
        (map thirdElem $ filter filterTuple primitives) ++
        (map thirdElem $ filter filterTuple ioPrimitives)
    where 
          filterTuple tuple = (== val) $ firstElem tuple
          firstElem (x, _, _) = x
          thirdElem (_, _, x) = x
eval _ (List [Atom "help", Atom val]) =
        return $ String $ concat $ 
        (map thirdElem $ filter filterTuple primitives) ++
        (map thirdElem $ filter filterTuple ioPrimitives)
    where 
          filterTuple tuple = (== val) $ firstElem tuple
          firstElem (x, _, _) = x
          thirdElem (_, _, x) = x
eval env (List (Atom "begin" : funs)) 
                        | null funs = eval env $ Nil ""
                        | length funs == 1 = eval env (head funs)
                        | otherwise = do
                                    let fs = tail funs
                                    _ <- eval env (head funs)
                                    eval env (List (Atom "begin" : fs))
eval env (Atom ident) = getVar env ident
eval env (List (function : args)) = do
                                        func <- eval env function
                                        argVals <- mapM (eval env) args
                                        apply func argVals
eval _ badForm = throwError $ BadSpecialForm "Unrecognized special form" badForm


makePort :: IOMode -> [LispVal] -> IOThrowsError LispVal
makePort mode [String filename] = liftM Port $ liftIO $ openFile filename mode
makePort _ badArgs = throwError $ BadSpecialForm "Cannot evaluate " $ head badArgs

closePort :: [LispVal] -> IOThrowsError LispVal
closePort [Port port] = liftIO $ hClose port >> return (Bool True)
closePort _ = return $ Bool False

readProc :: [LispVal] -> IOThrowsError LispVal
readProc [] = readProc [Port stdin]
readProc [Port port] = liftIO (hGetLine port) >>= liftThrows . readExpr
readProc badArgs = throwError $ BadSpecialForm "Cannot evaluate " $ head badArgs

writeProc :: [LispVal] -> IOThrowsError LispVal
writeProc [obj] = writeProc [obj, Port stdout]
writeProc [obj, Port port] = liftIO $ hPrint port obj >> return (Bool True)
writeProc badArgs = throwError $ BadSpecialForm "Cannot evaluate " $ head badArgs

readContents :: [LispVal] -> IOThrowsError LispVal
readContents [String filename] = liftM String $ liftIO $ readFile filename
readContents badArgs = throwError $ BadSpecialForm "Cannot evaluate " $ head badArgs 

load :: String -> IOThrowsError [LispVal]
load filename = liftIO (readFile filename) >>= liftThrows . readExprList

readAll :: [LispVal] -> IOThrowsError LispVal
readAll [String filename] = liftM List $ load filename
readAll badArgs = throwError $ BadSpecialForm "Cannot evaluate " $ head badArgs

apply :: LispVal -> [LispVal] -> IOThrowsError LispVal
apply (IOFunc func) args = func args
apply (PrimitiveFunc func) args = liftThrows $ func args
apply (Func (LispFun fparams varargs fbody fclosure)) args =
    if num fparams /= num args && isNothing varargs
        then throwError $ NumArgs (num fparams) args
        else liftIO (bindVars fclosure $ zip (map ((,) vnamespace) fparams) args) >>= bindVarArgs varargs >>= evalBody fbody
    where 
        remainingArgs = drop (length fparams) args
        num = toInteger . length
        evalBody ebody env = case ebody of
                                [lv] -> eval env lv
                                (lv : lvs) -> do
                                    _ <- eval env lv
                                    evalBody lvs env
                                _ -> throwError $ InternalError "Internal state error"
        bindVarArgs arg env = case arg of
            Just argName -> liftIO $ bindVars env [((vnamespace, argName), List remainingArgs)]
            Nothing -> return env
apply func args = throwError $ BadSpecialForm "Unable to evaluate form" $ List (func : args)

applyProc :: [LispVal] -> IOThrowsError LispVal
applyProc [func, List args] = apply func args
applyProc (func : args) = apply func args
applyProc badArgs = throwError $ BadSpecialForm "Cannot evaluate " $ head badArgs

makeFunc :: Monad m => Maybe String -> Env -> [LispVal] -> [LispVal] -> m LispVal
makeFunc varargs env p b = return $ Func $ LispFun (map showVal p) varargs b env

makeNormalFunc :: Env -> [LispVal] -> [LispVal] -> ExceptT LispError IO LispVal
makeNormalFunc = makeFunc Nothing

makeVarargs :: LispVal -> Env -> [LispVal] -> [LispVal] -> ExceptT LispError IO LispVal
makeVarargs = makeFunc . Just . showVal
